#import "NSThread-condensedStackTrace.h"

@implementation NSThread (HCondensedStackTrace)

+ (NSString*)condensedStackTrace {
  NSMutableArray *syms = [NSMutableArray array];
  @try {
    NSArray *stackSymbols = [NSThread callStackSymbols];
    NSString *ownSource = nil;
    NSUInteger i, lastAddedIndex = 9, count = [stackSymbols count];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    for (i = 1; i < count; i++) {
      NSString *entry = [stackSymbols objectAtIndex:i];
      NSScanner *scanner = [NSScanner scannerWithString:entry];
      [scanner setCharactersToBeSkipped:whitespace];
      NSString *source = nil, *symbol = nil;
      // 4  libSystem.B.dylib  0x00007fff84f8cc30  _Block_object_assign + 326
      if (![scanner scanInt:nil]) continue;
      if (![scanner scanUpToCharactersFromSet:whitespace intoString:&source])
        continue;
      if (![scanner scanUpToCharactersFromSet:whitespace intoString:nil])
        continue;
      [scanner scanUpToString:@" + " intoString:&symbol];
      NSString *prefix = (i > lastAddedIndex+1) ? @"  .." :
                         (i == 2 ? @"  ↑ " : @"    ");
      if (i == 1) {
        if (!ownSource) ownSource = source;
      } else if (ownSource && [ownSource isEqualToString:source]) {
        [syms addObject:[NSString stringWithFormat:@"%@%d %@", prefix, i-1,
                         symbol]];
        lastAddedIndex = i;
        if (i+2 >= count) break;
      } else if ((i == 2) || (i+2 >= count)) { // top caller or end
        [syms addObject:[NSString stringWithFormat:@"%@%d %@  <%@>", prefix,
                         i-1, symbol, source]];
        lastAddedIndex = i;
        if (i+2 >= count) break;
      }
    }
  } @catch(id e) { }
  return [syms componentsJoinedByString:@"\n"];
}

@end
