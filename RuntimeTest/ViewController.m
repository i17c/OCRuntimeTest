//
//  ViewController.m
//  RuntimeTest
//
//  Created by jason on 15/2/11.
//  Copyright (c) 2015年 chenyang. All rights reserved.
//

#import "ViewController.h"
#import <objc/runtime.h>
#import <objc/message.h>

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 消息动态解析
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
void fly2IMP(id target, SEL _cmd)
{
    NSLog(@"fly2IMP, method name: %@", NSStringFromSelector(_cmd));
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// meta class
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// http://www.cocoawithlove.com/2010/01/what-is-meta-class-in-objective-c.html, 译文：http://blog.jobbole.com/53824/
// http://blog.ibireme.com/2013/11/25/objc-object/
// 在 Class 对象上调用类方法不会返回 meta-class，而是再次返回 Class 对象
void ReportFunction(id self, SEL _cmd) {
    NSLog(@"This object is %p.", self);
    NSLog(@"Class is %@, and super is %@.", [self class], [self superclass]);
    
    Class currentClass = [self class];
    for (int i = 1; i < 5; i++)
    {
        NSLog(@"Following the isa pointer %d times gives %p, is meta: %@", i, currentClass, @(class_isMetaClass(currentClass)));
        currentClass = object_getClass(currentClass);
    }
    
    NSLog(@"NSObject's class is %p, is meta: %@", [NSObject class], @(class_isMetaClass([NSObject class])));
    NSLog(@"NSObject's meta class is %p, ismeta: %@", object_getClass([NSObject class]), @(class_isMetaClass(object_getClass([NSObject class]))));
}



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Horse & Fish & Bird
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface Horse : NSObject {
    
}

@end

@implementation Horse

- (void)running
{
    NSLog(@"Horse running!");
}

@end

@interface Fish : NSObject {

}

@end

@implementation Fish

- (void)swimming
{
    NSLog(@"fish swimming!");
}

@end

@interface Bird : NSObject {
    Fish * fish_;
    Horse * horse_;
}

- (void)fly:(NSInteger)time;

@end

@implementation Bird

- (instancetype)init
{
    self = [super init];
    if (self) {
        fish_ = [[Fish alloc] init];
        horse_ = [[Horse alloc] init];
    }
    
    return self;
}

+ (void)load
{
    NSLog(@"load");
}

+ (void)initialize
{
    NSLog(@"initialize");
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// 消息
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)fly:(NSInteger)time
{
    NSLog(@"time: %@", @(time));
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// 动态方法解析
/////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    NSLog(@"resolveInstanceMethod");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if (sel == @selector(fly2)) {
        // 动态添加方法，直接设置IMP，这里"v@:"是type encodeing，必须与IMP的参数一致才行
        // 官方guide，https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
        class_addMethod([self class], sel, (IMP)fly2IMP, "v@:"); // 动态添加方法
        return YES;
    }
#pragma clang diagnostic pop
    return [super resolveInstanceMethod:sel];
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////
// 消息转发
/////////////////////////////////////////////////////////////////////////////////////////////////////////

// 消息重定向机制
- (id)forwardingTargetForSelector:(SEL)aSelector
{
    NSLog(@"forwardingTargetForSelector");
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if (aSelector == @selector(running)) {
        return horse_;
    } else if (aSelector == @selector(fly3)) {
        return nil;
    }
#pragma clang diagnostic pop
    
    return [super forwardingTargetForSelector:aSelector];
}

// 转发
// forwardInvocation:消息发送前，Runtime系统会向对象发送methodSignatureForSelector:消息，并取到返回的方法签名用于生成NSInvocation对象。所以我们在重写forwardInvocation:的同时也要重写methodSignatureForSelector:方法，否则会抛异常。
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if (aSelector == @selector(fly3)) {
        return [fish_ methodSignatureForSelector:@selector(swimming)];
    }
#pragma clang diagnostic pop
    
    return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"forwardInvocation");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    if (anInvocation.selector == @selector(fly3)) {
        [anInvocation setSelector:@selector(swimming)];
        [anInvocation setTarget:fish_];
        [anInvocation invoke];
        return;
    }
#pragma clang diagnostic pop
    
    [super forwardInvocation:anInvocation];
}

// 无法识别方法
- (void)doesNotRecognizeSelector:(SEL)aSelector
{
    NSLog(@"doesNotRecognizeSelector");
    [super doesNotRecognizeSelector:aSelector];
}

@end

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ViewController
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // class & meta class
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    // http://www.cnblogs.com/kesalin/archive/2012/01/30/objc_create_class.html
    Class newClass = objc_allocateClassPair([NSError class], "RuntimeErrorSubclass", 0);
    class_addMethod(newClass, @selector(report), (IMP)ReportFunction, "v@:");
#pragma clang disgnostic pop
    objc_registerClassPair(newClass);
    
    id instanceOfNewClass = [[newClass alloc] initWithDomain:@"someDomain" code:0 userInfo:nil];
    [instanceOfNewClass performSelector:@selector(report)];
    
    
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // 消息
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
     Bird * bird = [[Bird alloc] init];
    
    // 获取Method中的IMP，然后使用指针和SEL直接调用IMP函数
    // 1. 这里methodForSelector方法是runtime提供的，并非OC自身的东西
    void (*f1)(id, SEL, NSInteger) = (void(*)(id, SEL, NSInteger))[bird methodForSelector:@selector(fly:)];
    for (NSInteger i = 0; i < 5; i ++) {
        f1(bird, @selector(fly:), i);
    }
    
    // 2. 使用class_getInstanceMethod方法来获取IMP进行执行
    Method method = class_getInstanceMethod([bird class], @selector(fly:));
    IMP imp = method_getImplementation(method);
    void (*f2)(id, SEL, NSInteger) = (void(*)(id, SEL, NSInteger))(imp);
    for (NSInteger i = 5; i < 10; i ++) {
        f2(bird, @selector(fly:), i);
    }
    
    // 3. 使用NSInvocation
    for (NSInteger i = 10; i < 15; i ++) {
        NSInvocation* invocation = [[NSInvocation alloc] init];
        [invocation setTarget:bird];
        [invocation setSelector:@selector(fly:)];
        [invocation setArgument:&i atIndex:2];
        [invocation invoke];
    }
    
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    // 动态方法解析
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    // resolveInstanceMethod，使用这种方法，一方面提供了一个可以动态提供方法实现的机会，例如属性中使用@dynamic propertyName;，这时，编译器就不再生成setPropertyName:和propertyName方法，而需要我们动态提供
    
    // If respondsToSelector: or instancesRespondToSelector: is invoked, the dynamic method resolver is given the opportunity to provide an IMP for the selector first.
    if ([bird respondsToSelector:@selector(fly2)]) {
        NSLog(@"fly2 respondsToSelector wroked!");
    }
    
    // 如果你想让该方法选择器被传送到转发机制，那么就让resolveInstanceMethod:返回NO。
    [bird performSelector:@selector(fly2) withObject:nil];
    
    
    
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    // 消息转发
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    //尽管转发很像继承，但是NSObject类不会将两者混淆。像respondsToSelector: 和 isKindOfClass:这类方法只会考虑继承体系，不会考虑转发链。这个时候，可以通过重写respondsToSelector: 方法来hack一下
    
    // 被forwardingTargetForSelector处理
    if ([bird respondsToSelector:@selector(running)]) {
        NSLog(@"running respondsToSelector wroked!");
    } else {
        NSLog(@"running respondsToSelector not wroked!");
    }
    [bird performSelector:@selector(running) withObject:nil];
    
    // 被forwardInvocation处理
    if ([bird respondsToSelector:@selector(fly3)]) {
        NSLog(@"fly3 respondsToSelector wroked!");
    } else {
        NSLog(@"fly3 respondsToSelector not wroked!");
    }
    [bird performSelector:@selector(fly3) withObject:nil];
    
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
    // doesNotRecognizeSelector
    /////////////////////////////////////////////////////////////////////////////////////////////////////////
//    [bird performSelector:@selector(fly4) withObject:nil];
}

@end
