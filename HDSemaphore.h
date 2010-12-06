#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

/*!
 * A counting semaphore (Objective-C wrapper around dispatch_semaphore) which
 * only calls to the kernel on contention.
 */
@interface HDSemaphore : NSObject {
  dispatch_semaphore_t dsema_;
}

/*!
 * Initialize a new counting semaphore with an initial value.
 *
 * @discussion
 * Passing zero for the value is useful for when two threads need to reconcile
 * the completion of a particular event. Passing a value greather than zero is
 * useful for managing a finite pool of resources, where the pool size is equal
 * to the value.
 *
 * @param value
 * The starting value for the semaphore. Passing a value less than zero will
 * cause NULL to be returned.
 *
 * @result
 * The newly created semaphore, or nil on failure.
 */
- (id)initWithValue:(long)value;

/*!
 * Get/wait for/decrement a semaphore.
 *
 * @discussion
 * Decrement the counting semaphore. If the resulting value is less than zero,
 * this function waits in FIFO order for a signal to occur before returning.
 *
 * @param timeout
 * When to timeout (see dispatch_time). As a convenience, there are the
 * DISPATCH_TIME_NOW and DISPATCH_TIME_FOREVER constants.
 *
 * @result
 * Returns YES on success, or NO if the timeout occurred.
 */
- (BOOL)getWithTimeout:(dispatch_time_t)timeout;

// Alias for -[getWithTimeout:DISPATCH_TIME_NOW]
- (BOOL)tryGet;

// Alias for -[getWithTimeout:DISPATCH_TIME_FOREVER]
- (void)get;

/*!
 * Put/signal/increment a semaphore.
 *
 * @discussion
 * Increment the counting semaphore. If the previous value was less than zero,
 * this function wakes a waiting thread before returning.
 *
 * @result
 * This function returns YES if a thread is woken. Otherwise, NO is returned.
 */
- (BOOL)put;

@end
