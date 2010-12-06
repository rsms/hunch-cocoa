#import "HUInsetPopUpButton.h"

@implementation HUInsetPopUpButton

- (id)initWithCoder:(NSCoder *)decoder {
	if (self = [super initWithCoder:decoder]) {
		[[self cell] setBackgroundStyle:NSBackgroundStyleRaised];
	}
	return self;
}

@end
