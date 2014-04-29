//
//  Copyright (c) 2013 Lukasz Wolanczyk. All rights reserved.
//

#import <objc/runtime.h>
#import "NSObject+NISERuntimeFake.h"

static char *const NISERealClassKey = "NISERealClass";

@implementation NSObject (NISERuntimeFake)

+ (Class)fakeClass {
    NSString *className = [NSString stringWithFormat:@"NISEFake%@", NSStringFromClass([self class])];
    [self assertClassNotExists:NSClassFromString(className)];

    Class class = objc_allocateClassPair([NSObject class], [className cStringUsingEncoding:NSUTF8StringEncoding], 0);
    return class;
}

+ (id)fake {
    Class fakeClass = [self fakeClass];
    id fake = [[fakeClass alloc] init];
    objc_setAssociatedObject(fake, NISERealClassKey, [self class], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [fake overrideInstanceMethod:@selector(superclass) withImplementation:^Class(id _self){
        return [self class];
    }];

    [fake overrideInstanceMethod:@selector(isKindOfClass:) withImplementation:^BOOL(id _self, Class aClass){
        return [[self class] isSubclassOfClass:aClass];
    }];

    [fake overrideInstanceMethod:@selector(isMemberOfClass:) withImplementation:^BOOL(id _self, Class aClass){
        return [self class] == aClass;
    }];

    [fake overrideInstanceMethod:@selector(respondsToSelector:) withImplementation:^BOOL(id _self, SEL selector){
        BOOL respondsToSelector = NO;
        if(class_getInstanceMethod([self class], selector)){
            respondsToSelector = YES;
        }else if(class_getInstanceMethod([fake class], selector)){
            respondsToSelector = YES;
        }
        return (BOOL) class_getInstanceMethod([self class], selector) || class_getInstanceMethod([fake class], selector);
    }];

    return fake;
}

+ (id)fakeObjectWithProtocol:(Protocol *)protocol includeOptionalMethods:(BOOL)optional {
    id fake = [self fake];
    [self addProtocolWithConformingProtocols:protocol toClass:[fake class] includeOptionalMethods:optional];

    [fake overrideInstanceMethod:@selector(conformsToProtocol:) withImplementation:^BOOL(id _self, Protocol *aProtocol){
        return [[fake class] conformsToProtocol:aProtocol];
    }];

    return fake;
}

- (void)overrideInstanceMethod:(SEL)selector withImplementation:(id)block {
    Class realClass = objc_getAssociatedObject(self, NISERealClassKey);
    Method method = class_getInstanceMethod(realClass, selector);
    if(method == nil){
        method = class_getInstanceMethod([self class], selector);
    }
    [self assertClassIsFake:method];
    [self assertMethodExists:method];
    if (method) {
        IMP implementation = imp_implementationWithBlock(block);
        class_replaceMethod([self class], selector, implementation, method_getTypeEncoding(method));
    }
}

#pragma mark - Helpers

+ (void)addProtocolWithConformingProtocols:(Protocol *)baseProtocol toClass:(Class)class includeOptionalMethods:(BOOL)optional {
    [self addMethodsFromProtocol:baseProtocol toClass:class includeOptionalMethods:optional];

    unsigned int protocolCount;
    __unsafe_unretained Protocol **protocols = protocol_copyProtocolList(baseProtocol, &protocolCount);

    for (int i = 0; i < protocolCount; i++) {
        Protocol *protocol = protocols[i];
        [self addProtocolWithConformingProtocols:protocol toClass:class includeOptionalMethods:optional];
    }
}

+ (void)addMethodsFromProtocol:(Protocol *)protocol toClass:(Class)class includeOptionalMethods:(BOOL)optional {
    if (protocol == @protocol(NSObject)) {
        return;
    }

    class_addProtocol(class, protocol);
    void (^enumerate)(BOOL) = ^(BOOL isRequired) {
        unsigned int descriptionCount;
        struct objc_method_description *methodDescriptions = protocol_copyMethodDescriptionList(protocol, isRequired, YES, &descriptionCount);
        for (int i = 0; i < descriptionCount; i++) {
            struct objc_method_description methodDescription = methodDescriptions[i];
            IMP implementation = imp_implementationWithBlock(^id {
                return nil;
            });
            class_addMethod(class, methodDescription.name, implementation, methodDescription.types);
        }
    };
    enumerate(YES);
    if (optional) {
        enumerate(NO);
    }
}

#pragma mark - Assertions

- (void)assertClassNotExists:(Class)aClass {
    NSString *description = [NSString stringWithFormat:@"Could not create %@ class, because class with such name already exists",
                                                       NSStringFromClass(aClass)];
    NSAssert(!aClass, description);
}

- (void)assertClassIsFake:(Method)method {
    Class aClass = [self class];
    NSString *description = [NSString stringWithFormat:@"Could not override method %@, because %@ is not a fake class",
                                                       NSStringFromSelector(method_getName(method)),
                                                       NSStringFromClass(aClass)];
    NSAssert([NSStringFromClass(aClass) hasPrefix:@"NISEFake"], description);
    NSAssert(!NSClassFromString(NSStringFromClass(aClass)), description);
}

- (void)assertMethodExists:(Method)method {
    NSString *description = [NSString stringWithFormat:@"Could not override method %@, because such method does not exist in %@ class",
                                                       NSStringFromSelector(method_getName(method)),
                                                       NSStringFromClass([self class])];
    NSAssert(method, description);
}

@end
