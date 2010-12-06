#import "HUInsetTextFieldCell.h"
#import "NSShadow+HUAdditions.h"

@implementation HUInsetTextFieldCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
	if (![self isHighlighted])
		[[NSShadow insetControlShadow] set];
	[super drawWithFrame:frame inView:view];
}

@end
