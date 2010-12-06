#import "HRefcountLogger.h"
#import "NSThread-condensedStackTrace.h"
#import <libkern/OSAtomic.h>


uint32_t nextSerialNumber = 0;

@implementation HRefcountLogger

@synthesize name = name_, logRetain = logRetain_, logRelease = logRelease_,
            logDealloc = logDealloc_, serialNumber = serialNumber_;

+ (id)loggerWithName:(NSString*)name {
  return [[[self alloc] initWithName:name] autorelease];
}

- (id)_init {
  self = [super init];
  serialNumber_ =
      OSAtomicIncrement32Barrier((volatile int32_t*)&nextSerialNumber);
  logRetain_ = logRelease_ = logDealloc_ = YES;
  return self;
}

- (id)initWithName:(NSString*)name {
  self = [self _init];
  name_ = [name retain];
  NSLog(@"%@ init (%lu)", self, [self retainCount]);
  return self;
}

- (id)init {
  self = [self _init];
  NSLog(@"%@ init (%lu)", self, [self retainCount]);
  return self;
}

- (BOOL)logRetainAndRelease {
  return logRetain_ && logRelease_;
}

- (void)setLogRetainAndRelease:(BOOL)y {
  logRetain_ = logRelease_ = y;
}

- (void)noop {}

- (id)retain {
  if (logRetain_)
      NSLog(@"%@ retain (before: %lu)\n%@", self, [self retainCount],
            [NSThread condensedStackTrace]);
  return [super retain];
}

- (void)release {
  if (logRelease_)
    NSLog(@"%@ release (before: %lu)\n%@", self, [self retainCount],
          [NSThread condensedStackTrace]);
  [super release];
}

- (void)dealloc {
  if (logDealloc_)
    NSLog(@"%@ dealloc\n%@", self, [NSThread condensedStackTrace]);
  [name_ release];
  [super dealloc];
}

- (NSString*)description {
  if (name_) {
    return [NSString stringWithFormat:@"⚑ %@", name_];
  } else {
    return [NSString stringWithFormat:@"⚑ %@#%u",
            NSStringFromClass([self class]), serialNumber_];
  }
}

@end
