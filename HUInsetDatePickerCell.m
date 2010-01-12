#import "HUInsetDatePickerCell.h"
#import "NSShadow+HUAdditions.h"

@implementation HUInsetDatePickerCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
	if (![self isHighlighted])
		[[NSShadow insetControlShadow] set];
	[super drawWithFrame:frame inView:view];
}

@end
