#import <Cocoa/Cocoa.h>

@interface NSObject (HEventEmitter)

/**
 * Shorthand for addListenerForEvent:usingBlock:, used like this:
 *   [foo on:@"bar", ^(id self) { ...
 */
#ifndef __cplusplus
- (void)on:(NSString*)eventName, ...;
#endif

// Shorthand for addListenerForEvent:usingBlock:
- (void)on:(NSString*)eventName call:(id)block;

// Register |block| to be called when |event| is emitted from the receiver
- (void)addListenerForEvent:(NSString *)name usingBlock:(id)block;

// Emit an event named |name| with |arguments|
- (void)emitEvent:(NSString*)name arguments:(NSArray*)arguments;

// Emit an event named |name| with single |argument|
- (void)emitEvent:(NSString*)name argument:(id)argument;

// Emit an event named |name| with variable arguments terminated by nil
- (void)emitEvent:(NSString*)name, ... __attribute__((sentinel));

// Emit an event named |name| with arguments in |argv| of length |argc|
- (void)emitEvent:(NSString*)name argv:(id*)argv argc:(NSUInteger)argc;

// Remove listener for a specific event
- (void)removeListener:(id)block forEvent:(NSString*)eventName;

// Remove listener for all events
- (void)removeListener:(id)block;

// Remove all listeners for event
- (void)removeAllListenersForEvent:(NSString*)eventName;

// Remove all listeners
- (void)removeAllListeners;

// Observe |notificationName| originating from |source| invoking |handler|
- (void)observe:(NSString*)notificationName
         source:(id)source
        handler:(SEL)handler;

// Post a notification with self as source
- (void)post:(NSString*)notificationName;

// Remove self as an observer for ALL registered observations
- (void)stopObserving;

// Remove self as an observer for |notificationName| from ANY source
- (void)stopObserving:(NSString*)notificationName;

// Remove self as an observer for |notificationName| from |source|
- (void)stopObserving:(NSString*)notificationName source:(id)source;

// Remove self as an observer for ANY notification from |source|
- (void)stopObservingObject:(id)source;

@end
