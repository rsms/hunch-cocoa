#import "HEventEmitter.h"
#import "HDSemaphore.h"
#import <objc/runtime.h>


static char gListenersKey;
static char gSemaphoreKey;

@implementation NSObject (HEventEmitter)

static Class gBlockClass;

+ (void)initialize {
  gBlockClass = [^{} class];
}


static inline BOOL _isBlockType(id obj) {
  const char *name = object_getClassName(obj);
  size_t len = strlen(name);
  return strcmp(name+(len-7), "Block__") == 0;
}


- (void)addListenerForEvent:(NSString *)name usingBlock:(id)block {
  if (!_isBlockType(block)) {
    [NSException raise:NSInvalidArgumentException
                format:@"unexpected block type %@",
                       NSStringFromClass([block class])];
  }
  block = [block copy];

  // get or create semaphore. There's potential for a race condition here.
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) {
    sem = [[HDSemaphore alloc] initWithValue:0];
    objc_setAssociatedObject(self, &gSemaphoreKey, sem,OBJC_ASSOCIATION_RETAIN);
  } else {
    [sem get];
  }
  @try {
    NSMutableArray *listeners;
    NSMutableDictionary *listenersDict =
        objc_getAssociatedObject(self, &gListenersKey);
    if (!listenersDict) {
      listeners = [NSMutableArray arrayWithObject:block];
      listenersDict =
          [NSMutableDictionary dictionaryWithObject:listeners forKey:name];
      objc_setAssociatedObject(self, &gListenersKey, listenersDict,
                               OBJC_ASSOCIATION_RETAIN);
    } else {
      if ((listeners = [listenersDict objectForKey:name])) {
        [listeners addObject:block];
      } else {
        listeners = [NSMutableArray arrayWithObject:block];
        [listenersDict setObject:listeners forKey:name];
      }
    }
    // release our copy'd ref to block (listeners array is now the owner)
    [block release];
  } @finally {
    [sem put];
  }
}


- (void)on:(NSString*)eventName, ... {
	void (^block)(void);
	va_list valist;
	va_start(valist, eventName);
	block = va_arg(valist, void(^)(void));
	va_end(valist);
  if (block)
    [self addListenerForEvent:eventName usingBlock:block];
}


// C++ does not support passing "non-POD types" for variadic args
- (void)on:(NSString*)eventName call:(id)block {
  [self addListenerForEvent:eventName usingBlock:block];
}


- (void)emit:(NSString*)eventName, ... {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];
  
  NSMutableArray *listeners;
  NSMutableDictionary *listenersDict =
      objc_getAssociatedObject(self, &gListenersKey);
  if (!listenersDict || !(listeners = [listenersDict objectForKey:eventName])) {
    [sem put];
    return;
  }
  // parse arguments
	va_list valist;
	va_start(valist, eventName);
  #define maxargs 8
  id args[maxargs] = {0,0,0,0,0,0,0,0};
  id arg;
  size_t count = 0;
  while ((arg = va_arg(valist, id)) && count < maxargs) {
    args[count++] = arg;
  }
	va_end(valist);
  // invoke listeners
  @try {
    for (id block in listeners) {
      #if !NDEBUG  // since we might use injected debuggers
      if (!_isBlockType(block)) continue;
      #endif
      ((void(^)(id,id,id,id,id,id,id,id))block)(args[0],args[1],
                args[2],args[3],args[4],args[5],args[6],args[7]);
    }
  } @finally {
    [sem put];
  }
}


- (void)removeListener:(id)block forEvent:(NSString*)eventName {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];
  NSMutableArray *listeners;
  NSMutableDictionary *listenersDict =
      objc_getAssociatedObject(self, &gListenersKey);
  if (listenersDict && (listeners = [listenersDict objectForKey:eventName])) {
    [listeners removeObject:block];
  }
  [sem put];
}


- (void)removeListener:(id)block {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];
  NSMutableDictionary *listenersDict =
      objc_getAssociatedObject(self, &gListenersKey);
  if (listenersDict) {
    [listenersDict enumerateKeysAndObjectsUsingBlock:^(id key, id val, BOOL *s) {
      [(NSMutableArray*)val removeObject:block];
    }];
  }
  [sem put];
}


- (void)removeAllListenersForEvent:(NSString*)eventName {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];
  NSMutableDictionary *listenersDict =
      objc_getAssociatedObject(self, &gListenersKey);
  if (listenersDict)
    [listenersDict removeObjectForKey:eventName];
  [sem put];
}


- (void)removeAllListeners {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];
  objc_setAssociatedObject(self, &gListenersKey, nil, OBJC_ASSOCIATION_RETAIN);
  [sem put];
  [sem retain];
  objc_setAssociatedObject(self, &gSemaphoreKey, nil, OBJC_ASSOCIATION_RETAIN);
  [sem release];
}


@end
