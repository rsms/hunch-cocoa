#import "NSError+HUAdditions.h"

@implementation NSError (HUAdditions)

+ (NSError *)errorWithDescription:(NSString *)msg code:(NSInteger)code {
	return [NSError errorWithDomain:@"HUError" code:code userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]];
}

+ (NSError *)errorWithDescription:(NSString *)msg {
	return [NSError errorWithDescription:msg code:0];
}

+ (NSError *)errorWithCode:(NSInteger)code format:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError errorWithDescription:msg code:code];
}

+ (NSError *)errorWithFormat:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError errorWithDescription:msg code:0];
}

@end
