@interface NSError (HUAdditions)
+ (NSError *)errorWithDescription:(NSString *)msg code:(NSInteger)code;
+ (NSError *)errorWithDescription:(NSString *)msg;
+ (NSError *)errorWithCode:(NSInteger)code format:(NSString *)format, ...;
+ (NSError *)errorWithFormat:(NSString *)format, ...;
@end
