#import <Cocoa/Cocoa.h>

#ifndef WARN_UNUSED
  #ifndef __cplusplus
    #define WARN_UNUSED __attribute__((warn_unused_result))
  #else
    #define WARN_UNUSED
  #endif
#endif

@interface HRefcountLogger : NSObject {
  uint32_t serialNumber_;
  NSString *name_;
  BOOL logRetain_;
  BOOL logRelease_;
  BOOL logDealloc_;
}
@property(readonly) uint32_t serialNumber;
@property(retain) NSString *name;
@property(assign) BOOL logRetain;
@property(assign) BOOL logRelease;
@property(assign) BOOL logRetainAndRelease;
@property(assign) BOOL logDealloc;
+ (id)loggerWithName:(NSString*)name WARN_UNUSED;
- (id)initWithName:(NSString*)name WARN_UNUSED;
- (id)init WARN_UNUSED;
- (void)noop;
@end
