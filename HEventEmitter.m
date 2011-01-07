#import "HEventEmitter.h"
#import "HDSemaphore.h"
#import <objc/runtime.h>


static char gListenersKey;
static char gSemaphoreKey;
static Class gBlockClass;

static void __attribute__((constructor(0))) __NSObject_HEventEmitter_init() {
  gBlockClass = [^{} class];
}

@implementation NSObject (HEventEmitter)


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
  block = Block_copy(block);

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


#define _ARGC_MAX 8
#define _EXEC_BLOCK_VA(block, ...) \
  ((BOOL(^)(id,id,id,id,id,id,id,id))(block))(__VA_ARGS__)


/*- (void)onNext:(NSString*)eventName call:(id)block {
  __block id self_ = self;
  __block id block2;
  dispatch_block_t block1 = Block_copy((dispatch_block_t)block);
  block2 = ^(id a1, id a2, id a3, id a4, id a5, id a6, id a7, id a8) {
    _EXEC_BLOCK_VA(block1, a1, a2, a3, a4, a5, a6, a7, a8);
    Block_release(block1);
    return YES;
  };
  [self addListenerForEvent:eventName usingBlock:block2];
}*/


- (void)emitEvent:(NSString*)name argv:(id*)argv argc:(NSUInteger)argc {
  HDSemaphore *sem = objc_getAssociatedObject(self, &gSemaphoreKey);
  if (!sem) return; // no listeners
  [sem get];

  NSMutableArray *listeners;
  NSMutableDictionary *listenersDict =
      objc_getAssociatedObject(self, &gListenersKey);
  if (!listenersDict || !(listeners = [listenersDict objectForKey:name]) ||
      listeners.count == 0) {
    [sem put];
    return;
  }
  // we take a shallow snapshot of listeners so that we can release the
  // semaphore before calling any blocks, which might in turn call some of our
  // other methods which aquires the semaphore. One use-case is to call
  // removeListener from within a block. This design is to avoid ending up in a
  // deadlock state.
  NSArray *listeners2 = [listeners copy];
  [sem put];
  // invoke listeners
  for (id block in listeners2) {
    #if !NDEBUG  // since we might use injected debuggers
    if (!_isBlockType(block)) continue;
    #endif
    BOOL remove = _EXEC_BLOCK_VA(block,
      argc > 0 ? argv[0] : nil,
      argc > 1 ? argv[1] : nil,
      argc > 2 ? argv[2] : nil,
      argc > 3 ? argv[3] : nil,
      argc > 4 ? argv[4] : nil,
      argc > 5 ? argv[5] : nil,
      argc > 6 ? argv[6] : nil,
      argc > 7 ? argv[7] : nil);
    if (remove) {
      [self removeListener:block];
    }
  }
  [listeners2 release];
}


- (void)emitEvent:(NSString*)name arguments:(NSArray*)arguments {
  NSUInteger argc = MIN(_ARGC_MAX, arguments.count);
  id argv[_ARGC_MAX];
  [arguments getObjects:argv range:NSMakeRange(0, argc)];
  [self emitEvent:name argv:argv argc:argc];
}


- (void)emitEvent:(NSString*)name argument:(id)argument {
  [self emitEvent:name argv:(argument ? &argument : nil) argc:0];
}


- (void)emitEvent:(NSString*)name, ... {
  va_list valist;
  va_start(valist, name);
  id args[_ARGC_MAX];
  id arg;
  size_t count = 0;
  while ((arg = va_arg(valist, id)) && count < _ARGC_MAX) {
    args[count++] = arg;
  }
  va_end(valist);
  [self emitEvent:name argv:args argc:count];
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


- (void)observe:(NSString*)notificationName
         source:(id)source
        handler:(SEL)handler {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self selector:handler name:notificationName object:source];
}


- (void)post:(NSString*)notificationName {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:notificationName object:self];
}

- (void)post:(NSString*)notificationName userInfo:(NSDictionary*)userInfo {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:notificationName object:self userInfo:userInfo];
}

- (void)post:(NSString*)notificationName
  userObject:(id)userInfoObject
      forKey:(id)userInfoKey {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSDictionary *userInfo = [NSDictionary dictionaryWithObject:userInfoObject
                                                       forKey:userInfoKey];
  [nc postNotificationName:notificationName object:self userInfo:userInfo];
}

- (void)stopObserving {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stopObserving:(NSString*)notificationName {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:notificationName
                                                object:nil];
}

- (void)stopObserving:(NSString*)notificationName source:(id)source {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:notificationName
                                                object:source];
}

- (void)stopObservingObject:(id)source {
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:nil
                                                object:source];
}


@end
