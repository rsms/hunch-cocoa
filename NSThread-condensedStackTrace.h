#import <Cocoa/Cocoa.h>

@interface NSThread (HCondensedStackTrace)

// A condensed, formatted stack trace suitable for logging and debugging
+ (NSString*)condensedStackTrace;

@end
