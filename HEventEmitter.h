#import <Cocoa/Cocoa.h>

@interface NSObject (HEventEmitter)

/**
 * Shorthand for addListenerForEvent:usingBlock:, used like this:
 *   [foo on:@"bar", ^(id self) { ...
 */
- (void)on:(NSString*)eventName, ...;

// Register |block| to be called when |event| is emitted from the receiver
- (void)addListenerForEvent:(NSString *)name usingBlock:(id)block;

// Emit an event with variable arguments terminated by nil
- (void)emit:(NSString*)eventName, ... __attribute__((sentinel));

// Remove listener for a specific event
- (void)removeListener:(id)block forEvent:(NSString*)eventName;

// Remove listener for all events
- (void)removeListener:(id)block;

// Remove all listeners for event
- (void)removeAllListenersForEvent:(NSString*)eventName;

// Remove all listeners
- (void)removeAllListeners;

@end
