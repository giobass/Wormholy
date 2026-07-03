//
//  URLSessionWebSocketTask+Wormholy.m
//  Wormholy-SDK
//
//  Created by Giovanni Bassolino on 03/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//
//  Swizzles NSURLSessionWebSocketTask's send/receive methods directly in Objective-C.
//  Their message payload (`NSURLSessionWebSocketMessage *`) isn't representable in Swift's
//  `@objc`, so this can't be done via a Swift extension the way the rest of Wormholy's
//  swizzling is - see WebSocketInterceptor.swift for the counterpart handling the
//  WebSocket factory methods and `cancel(with:reason:)`.
//
//  `-[NSURLSessionWebSocketTask sendMessage:completionHandler:]` and
//  `receiveMessageWithCompletionHandler:` aren't actually implemented on the public
//  NSURLSessionWebSocketTask class - `[session webSocketTaskWithURL:]` returns an instance
//  of a private concrete subclass that provides the real implementation. Swizzling the
//  public class's method table has no effect on those instances, so this swizzles the
//  *actual* runtime class of each task instead, the first time one is seen.

#import "URLSessionWebSocketTask+Wormholy.h"
#import "WormholyMethodSwizzling.h"
#import <objc/runtime.h>

#if SWIFT_PACKAGE
@import WormholySwift;
#else
#import <Wormholy/Wormholy-Swift.h>
#endif

typedef void (^WHSendCompletion)(NSError * _Nullable);
typedef void (^WHReceiveCompletion)(NSURLSessionWebSocketMessage * _Nullable, NSError * _Nullable);

typedef void (*WHSendIMP)(id, SEL, NSURLSessionWebSocketMessage *, WHSendCompletion);
typedef void (*WHReceiveIMP)(id, SEL, WHReceiveCompletion);

static NSMutableSet<NSValue *> *wormholySwizzledClasses;
static NSMutableDictionary<NSValue *, NSValue *> *wormholyOrigSendIMPs;
static NSMutableDictionary<NSValue *, NSValue *> *wormholyOrigReceiveIMPs;

static void recordSentOrErrored(NSURLSessionWebSocketTask *task, NSURLSessionWebSocketMessage *message, NSError * _Nullable error) {
    if (![WHWebSocketRecorder isEnabled]) return;

    if (error) {
        [WHWebSocketRecorder recordError:task error:error];
    } else if (message.type == NSURLSessionWebSocketMessageTypeString) {
        [WHWebSocketRecorder recordSentText:task text:message.string ?: @""];
    } else {
        [WHWebSocketRecorder recordSentData:task data:message.data ?: [NSData data]];
    }
}

static void recordReceivedOrErrored(NSURLSessionWebSocketTask *task, NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
    if (![WHWebSocketRecorder isEnabled]) return;

    if (error) {
        [WHWebSocketRecorder recordError:task error:error];
    } else if (message.type == NSURLSessionWebSocketMessageTypeString) {
        [WHWebSocketRecorder recordReceivedText:task text:message.string ?: @""];
    } else if (message) {
        [WHWebSocketRecorder recordReceivedData:task data:message.data ?: [NSData data]];
    }
}

static void Wormholy_sendMessage(NSURLSessionWebSocketTask *self, SEL _cmd, NSURLSessionWebSocketMessage *message, WHSendCompletion completionHandler) {
    WHSendIMP orig = NULL;
    @synchronized (wormholyOrigSendIMPs) {
        orig = [wormholyOrigSendIMPs[[NSValue valueWithNonretainedObject:object_getClass(self)]] pointerValue];
    }
    if (!orig) {
        if (completionHandler) {
            completionHandler([NSError errorWithDomain:@"WormholyWebSocket"
                                                  code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"Wormholy could not find the original WebSocket send implementation."}]);
        }
        return;
    }

    orig(self, _cmd, message, ^(NSError * _Nullable error) {
        recordSentOrErrored(self, message, error);
        if (completionHandler) completionHandler(error);
    });
}

static void Wormholy_receiveMessage(NSURLSessionWebSocketTask *self, SEL _cmd, WHReceiveCompletion completionHandler) {
    WHReceiveIMP orig = NULL;
    @synchronized (wormholyOrigReceiveIMPs) {
        orig = [wormholyOrigReceiveIMPs[[NSValue valueWithNonretainedObject:object_getClass(self)]] pointerValue];
    }
    if (!orig) {
        if (completionHandler) {
            completionHandler(nil, [NSError errorWithDomain:@"WormholyWebSocket"
                                                       code:2
                                                   userInfo:@{NSLocalizedDescriptionKey: @"Wormholy could not find the original WebSocket receive implementation."}]);
        }
        return;
    }

    orig(self, _cmd, ^(NSURLSessionWebSocketMessage * _Nullable message, NSError * _Nullable error) {
        recordReceivedOrErrored(self, message, error);
        if (completionHandler) completionHandler(message, error);
    });
}

/// Exposed to Swift via `NSClassFromString` + `perform(_:with:)` (no compile-time dependency
/// from WormholySwift on WormholyObjC), called the first time each WebSocket factory method
/// attaches a model to a task - see `WebSocketInterceptor.ensureSwizzledForActualClass`.
@interface WHWebSocketTaskSwizzler : NSObject
@end

@implementation WHWebSocketTaskSwizzler

+ (void)load {
    wormholySwizzledClasses = [NSMutableSet set];
    wormholyOrigSendIMPs = [NSMutableDictionary dictionary];
    wormholyOrigReceiveIMPs = [NSMutableDictionary dictionary];
}

+ (void)wormholy_ensureSwizzledFor:(NSURLSessionWebSocketTask *)task {
    Class cls = object_getClass(task);
    NSValue *classKey = [NSValue valueWithNonretainedObject:cls];

    @synchronized (wormholySwizzledClasses) {
        if ([wormholySwizzledClasses containsObject:classKey]) return;
        [wormholySwizzledClasses addObject:classKey];
    }

    Method sendMethod = class_getInstanceMethod(cls, @selector(sendMessage:completionHandler:));
    Method receiveMethod = class_getInstanceMethod(cls, @selector(receiveMessageWithCompletionHandler:));
    IMP origSend = sendMethod ? method_getImplementation(sendMethod) : NULL;
    IMP origReceive = receiveMethod ? method_getImplementation(receiveMethod) : NULL;

    if (origSend) {
        WormholyReplaceMethod(@selector(sendMessage:completionHandler:), (IMP)Wormholy_sendMessage, cls, NO);
    }
    if (origReceive) {
        WormholyReplaceMethod(@selector(receiveMessageWithCompletionHandler:), (IMP)Wormholy_receiveMessage, cls, NO);
    }

    @synchronized (wormholyOrigSendIMPs) {
        wormholyOrigSendIMPs[classKey] = [NSValue valueWithPointer:origSend];
    }
    @synchronized (wormholyOrigReceiveIMPs) {
        wormholyOrigReceiveIMPs[classKey] = [NSValue valueWithPointer:origReceive];
    }
}

@end
