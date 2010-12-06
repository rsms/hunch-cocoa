#import "HDSemaphore.h"

@implementation HDSemaphore

- (id)initWithValue:(long)value {
  self = [super init];
  dsema_ = dispatch_semaphore_create(value);
  return self;
}

// Returns YES on success, or NO if the timeout occurred.
- (BOOL)getWithTimeout:(dispatch_time_t)timeout {
  return dispatch_semaphore_wait(dsema_, timeout) == 0;
}

// Returns YES on success, or NO if there are no references to get.
- (BOOL)tryGet {
  return dispatch_semaphore_wait(dsema_, DISPATCH_TIME_NOW) == 0;
}

- (void)get {
  dispatch_semaphore_wait(dsema_, DISPATCH_TIME_FOREVER);
}

// Returns YES if this woke up someone waiting on a -[get]
- (BOOL)put {
  return dispatch_semaphore_signal(dsema_) != 0;
}

- (void)dealloc {
  dispatch_release(dsema_);
  [super dealloc];
}

@end
