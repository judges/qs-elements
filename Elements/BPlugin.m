//
//  BPlugin.m
//  Elements
//
//
//  Copyright 2006 Elements. All rights reserved.
//

#import "BPlugin.h"
#import "BExtensionPoint.h"
#import "BExtension.h"
#import "BRequirement.h"
#import "BRegistry.h"
#import "BLog.h"

#import "NSXMLElement+BExtensions.h"

NSString *kBPluginWillLoadNotification = @"kBPluginWillLoadNotification";
NSString *kBPluginDidLoadNotification = @"kBPluginDidLoadNotification";
NSString *kBPluginWillRegisterNotification = @"kBPluginWillRegisterNotification";
NSString *kBPluginDidRegisterNotification = @"kBPluginDidRegisterNotification";

@interface BPlugin (Private)
- (NSURL *)pluginURL;
- (void)setPluginURL:(NSURL *)url; 
@end

@implementation BPlugin

#pragma mark init

static NSInteger BPluginLoadSequenceNumbers = 0;

- (id)initWithPluginURL:(NSURL *)url bundle:(NSBundle *)aBundle insertIntoManagedObjectContext:(NSManagedObjectContext*)context{
	if (!url) {
		[self release];
		return nil;
	}

	NSEntityDescription *entity = [NSEntityDescription entityForName:@"plugin" inManagedObjectContext:context];
    self = [self initWithEntity:entity insertIntoManagedObjectContext:context];
	if (self) {
        [self setPluginURL:url];
		[self setBundle:aBundle];

        int loadSeq = ([bundle isLoaded] ? BPluginLoadSequenceNumbers++ : NSNotFound);

		[self setValue:[NSNumber numberWithInteger:loadSeq]
                forKey:@"loadSequenceNumber"];

		BLogInfo(@"Creating Plugin [%@]", [(bundle ? [bundle bundlePath] : [url path]) lastPathComponent]);

		if (![self loadPluginXMLAttributes]) {
			BLogError([NSString stringWithFormat:@"failed loadPluginXMLAttributes for bundle %@", [bundle bundleIdentifier]]);
            [context deleteObject:self];
			[self release];
			return nil;
		}
	}
	return self;
}

- (BOOL)registerPlugin {
	if (registered) return YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:kBPluginWillRegisterNotification object:self userInfo:nil]; 
	BOOL success = [self loadPluginXMLContent];
	if (success) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kBPluginDidRegisterNotification object:self userInfo:nil]; 	
		[self setValue:[NSDate date] forKey:@"registrationDate"];
		return YES;
	}
	return NO;
}

#pragma mark dealloc
- (void)dealloc {
    [bundle release];
    [info release];
    [super dealloc];
}

#pragma mark accessors
- (void)awakeFromFetch {
	[super awakeFromFetch];
	[self bundle]; // Find the bundle
}

- (void)didTurnIntoFault {
	//BLogDebug(@"faulted %@", self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"identifier: %@ loadSequence: %i", [self identifier], [self loadSequenceNumber]];
}

- (NSBundle *)bundle {
    // Find our bundle, if possible
	if (!bundle) {
		NSString *path = [[self pluginURL] path];
		int location = [path rangeOfString:@"Contents/" options:NSBackwardsSearch|NSLiteralSearch].location;
		if (location != NSNotFound) {
			path = [path substringToIndex:location];
			[self setBundle:[NSBundle bundleWithPath:path]];
		}
	}
	return bundle;
}

- (void)setBundle:(NSBundle *)value {
    if (bundle != value) {
        [bundle autorelease];
        bundle = [value retain];
		[self setPrimitiveValue:[value bundleIdentifier]
                     forKey:@"id"];
  }
}

- (NSInteger)loadSequenceNumber {
	return loadSequenceNumber;
}

- (NSString *)author {
	return [[self info] firstValueForName:@"author"];	
}

- (NSString *)xmlPath {
	return [[self bundle] pathForResource:@"plugin" ofType:@"xml"];
}

- (NSString *)protocolsPath {
	return [[self bundle] pathForResource:[[[[self bundle] executablePath] lastPathComponent] stringByAppendingString:@"Protocols"] ofType:@"h"];
}



- (NSString *)identifier { return [self primitiveValueForKey:@"id"]; }

// Primitive Accessors 
#define PRIMITIVE_VALUE [self primitiveValueForKey:NSStringFromSelector(_cmd)]

- (NSString *)name { return PRIMITIVE_VALUE; }
- (NSString *)version { return PRIMITIVE_VALUE; }
- (NSArray *)requirements { return PRIMITIVE_VALUE; }
- (NSArray *)extensions { return PRIMITIVE_VALUE; }
- (NSArray *)extensionPoints { return PRIMITIVE_VALUE; }

- (BOOL)enabled {
	return YES;
}

- (void)setPluginURL:(NSURL *)url {
    [self setValue:[url absoluteString] forKey:@"url"];
}

- (NSURL *)pluginURL {
	NSString *urlString = [self valueForKey:@"url"];
	NSURL *url = urlString ? [NSURL URLWithString:urlString] : nil;
    return url;
}

- (NSManagedObject *)scanElement:(NSXMLElement *)elementInfo forPoint:(NSString *)point {
	NSManagedObject *element = [NSEntityDescription insertNewObjectForEntityForName:@"element"
                                                           inManagedObjectContext:[self managedObjectContext]];
	BLogDebug(@"element: %@, point: %@, attributes: %@", elementInfo, point, [elementInfo attributesAsDictionary]);
	[element setValuesForKeysWithDictionary:[elementInfo attributesAsDictionary]];
	[element setValue:self forKey:@"plugin"];
	[element setValue:point forKey:@"point"];
	
	[element setValue:[elementInfo XMLString] forKey:@"content"];
	return element;
}

#pragma mark loading
- (BOOL)scanExtensionPoint:(NSXMLElement *)extensionPointInfo {
	
	NSDictionary *pointAttributes = [extensionPointInfo attributesAsDictionary];
	NSString *identifier = [pointAttributes objectForKey:@"id"];
	
	NSManagedObject *point = [[BRegistry sharedInstance] extensionPointWithID:identifier];
	if (point) BLogDebug(@"using existing point %@", identifier);
	if (!point) {
		point = [NSEntityDescription insertNewObjectForEntityForName:@"extensionPoint"
                                          inManagedObjectContext:[self managedObjectContext]];
	}
	[point setValuesForKeysWithDictionary:pointAttributes];
	
	//BLog(@"[extensionPointInfo XMLString] %@", [extensionPointInfo XMLString]);
	[point setValue:[extensionPointInfo XMLString] forKey:@"content"];
	
	NSMutableSet *points = [self mutableSetValueForKey:@"extensionPoints"];
	[points addObject:point];
	[point setValue:self forKey:@"plugin"];
	
	return YES;
}


- (BOOL)scanExtension:(NSXMLElement *)extensionInfo {
	//BLog(@"extension %@", extensionInfo);
	NSManagedObject *extension = [NSEntityDescription insertNewObjectForEntityForName:@"extension"
                                                             inManagedObjectContext:[self managedObjectContext]];
	
	NSMutableSet *extensions = [self mutableSetValueForKey:@"extensions"];
	[extensions addObject:extension];
	NSDictionary *attributeDict = [extensionInfo attributesAsDictionary];
    [extension setValuesForKeysWithDictionary:attributeDict];
	[extension setValue:self forKey:@"plugin"];
    BLogDebug(@"extension: %@, attributes: %@", extension, attributeDict);
	NSString *point = [attributeDict objectForKey:@"point"];
    
	BExtensionPoint *extensionPoint = [[BRegistry sharedInstance] extensionPointWithID:point];
	if (!extensionPoint) {
        BLogError(@"Undefined extension point %@", point);
        return NO;
//        BLogWarn(@"Creating missing extension point %@ !", point);
//		extensionPoint = [NSEntityDescription insertNewObjectForEntityForName:@"extensionPoint"
//                                                       inManagedObjectContext:[self managedObjectContext]];
//		[extensionPoint setValue:point forKey:@"id"];
//        [extensionPoint setValue:self forKey:@"plugin"];
	}
    
	NSMutableSet *pluginElements = [self mutableSetValueForKey:@"elements"];
	NSMutableSet *extensionElements = [extension mutableSetValueForKey:@"elements"];
	for (int i = 0,  count = [extensionInfo childCount]; i < count; i++) {
		NSManagedObject *element = [self scanElement:(NSXMLElement *)[extensionInfo childAtIndex:i]
                                        forPoint:point];
		
		[pluginElements addObject:element];
		[extensionElements addObject:element];
	}
    
	return YES;
}

- (NSXMLDocument *)pluginXMLDocument {
	if (!pluginXMLDocument) {
		NSURL *pluginURL = [self pluginURL];
		
		if (!pluginURL) {
			BLogError(@"failed to find plugin.xml for bundle %@", bundle);
			return nil;
		}
        
		NSError *error = nil;
		pluginXMLDocument = [[NSXMLDocument alloc] initWithContentsOfURL:pluginURL
                                                                 options:NSXMLDocumentValidate
                                                                   error:&error];
		if (!pluginXMLDocument) {
			BLogError(@"failed to parse plugin.xml file %@ - %@", pluginURL, error);
			return nil;
		}
	}
	return pluginXMLDocument;
}

- (BOOL)loadPluginXMLAttributes {
	[self setValue:[[[self bundle] infoDictionary] objectForKey:(NSString *)kCFBundleIdentifierKey] forKey:@"id"];

    NSInteger versionInt = 0;
    NSString *versionString = [[[self bundle] infoDictionary] objectForKey:(NSString *)kCFBundleVersionKey];
    NSScanner *versionScanner = [NSScanner scannerWithString:versionString];

    [versionScanner scanInteger:&versionInt];

	[self setValue:[NSNumber numberWithInteger:versionInt] forKey:@"version"];
	[self setValue:[[[self bundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"displayVersion"];
	[self setValue:[[[self bundle] infoDictionary] objectForKey:(NSString *)kCFBundleNameKey] forKey:@"name"];
	return YES;
}

- (BOOL)loadPluginXMLContent {
	NSXMLDocument *document = [self pluginXMLDocument];
	NSXMLElement *root = [document rootElement];
	
    if (!root)
        return NO;

    for (NSXMLElement *element in [[root firstElementWithName:@"requirements"] elementsForName:@"requirement"]) {
		NSManagedObject *requirement = [NSEntityDescription insertNewObjectForEntityForName:@"requirement"
                                                                 inManagedObjectContext:[self managedObjectContext]];
		NSMutableDictionary *attributeDict = [NSMutableDictionary dictionaryWithDictionary:[element attributesAsDictionary]];
        
        /* Tweak up some of those */
        NSString *optionalStr = [attributeDict objectForKey:@"optional"];
        BOOL optionalBool = [optionalStr isEqualToString:@"true"] || [optionalStr isEqualToString:@"t"]
        || [optionalStr isEqualToString:@"yes"] || [optionalStr isEqualToString:@"y"]
        || [optionalStr isEqualToString:@"1"];
        [attributeDict setObject:[NSNumber numberWithBool:optionalBool] forKey:@"optional"];
        
		[requirement setValuesForKeysWithDictionary:attributeDict];
        [requirement setValue:self forKey:@"plugin"];
	}
    NSXMLElement *infoElement = [root firstElementWithName:@"info"];
	[self setValue:[infoElement XMLString] forKey:@"info"];
    
	NSXMLElement *extensionsChildren = [root firstElementWithName:@"extensions"];
	
	NSArray *points = [extensionsChildren elementsForName:@"extension-point"];
	for (int i = 0,  count = [points count]; i < count; i++) {
		[self scanExtensionPoint:[points objectAtIndex:i]];
	}
	NSArray *extensions = [extensionsChildren elementsForName:@"extension"];
	for (int i = 0,  count = [extensions count]; i < count; i++) {
		[self scanExtension:[extensions objectAtIndex:i]];
	}
	return YES;
}

- (BOOL)isLoaded {
	return [bundle isLoaded];
}

- (BOOL)load:(NSError **)error {
    if (![bundle isLoaded]) {
		if (![self enabled]) {
			BLogError(@"Failed to load plugin %@ because it isn't enabled.", [self identifier]);
			return NO;
		}
		
		NSEnumerator *enumerator = [[self requirements] objectEnumerator];
		BRequirement *eachImport;
		
		while ((eachImport = [enumerator nextObject])) {
			if (![eachImport isLoaded]) {
				if ([eachImport load:error]) {
                    /* TODO: Check requirement version */
					BLogInfo(@"Loaded code for requirement %@ by plugin %@", eachImport, [self identifier]);
				} else {
					if ([eachImport optional]) {
						BLogWarn(@"Failed to load code for optional requirement %@ by plugin %@", eachImport, [self identifier]);
					} else {
						BLogError(@"Failed to load code for requirement %@ by plugin %@", eachImport, [self identifier]);
						BLogError(@"Failed to load code for plugin with identifier %@", [self identifier]);
						return NO;
					}
				}
			}
		}
		
		[[NSNotificationCenter defaultCenter] postNotificationName:kBPluginWillLoadNotification object:self userInfo:nil]; 
        NSError *bundleError = nil;
		if ([bundle loadAndReturnError:&bundleError]) {
            [self willChangeValueForKey:@"isLoaded"];
            [self didChangeValueForKey:@"isLoaded"];

			[[NSNotificationCenter defaultCenter] postNotificationName:kBPluginDidLoadNotification object:self userInfo:nil];
			[self setValue:[NSNumber numberWithInt: BPluginLoadSequenceNumbers++]
                    forKey:@"loadSequenceNumber"];
			BLogInfo(@"Loaded plugin %@", [self identifier]);
		} else {
			BLogError(@"Failed to load bundle with identifier %@: %@ => %@", [self identifier], bundle, bundleError);
            if (error)
                *error = bundleError;
			return NO;
		}
        
    }
    
    return YES;
}

- (NSXMLElement *)info {
	if (!info) {
		NSString *infoString = [self primitiveValueForKey:@"info"];
		if (!infoString) return nil;
		info = [[[[NSXMLDocument alloc] initWithXMLString:infoString
                                                  options:0
                                                    error:nil] autorelease] rootElement];
		[info retain];
	}
    return [[info retain] autorelease];
}

- (void)setInfo:(NSXMLElement *)value {
    if (info != value) {
        [info release];
        info = [value copy];
    }
}

- (id)valueForUndefinedKey:(NSString *)key {
    id value = nil;
    value = [[self info] firstElementWithName:key];
    if (value != nil)
        return value;

    value = [[[self bundle] infoDictionary] objectForKey:key];
    if (value != nil)
        return value;

    return [super valueForUndefinedKey:key];
}

@end
