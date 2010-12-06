#import "NSShadow+HUAdditions.h"

@implementation NSShadow (HUAdditions)

static NSShadow *_insetControlShadow = nil;

+ (NSShadow *)insetControlShadow {
	if (_insetControlShadow == nil) {
		_insetControlShadow = [[NSShadow alloc] init];
		[_insetControlShadow setShadowColor:[NSColor colorWithDeviceWhite:1.0 alpha:0.5]];
		[_insetControlShadow setShadowOffset:NSMakeSize(0.0, -1.0)];
	}
	return _insetControlShadow;
}

static NSShadow *_insetDropShadow = nil;

+ (NSShadow *)insetDropShadow {
	if (_insetDropShadow == nil) {
		_insetDropShadow = [[NSShadow alloc] init];
		[_insetDropShadow setShadowColor:[NSColor colorWithDeviceWhite:0.0 alpha:1.0]];
		[_insetDropShadow setShadowOffset:NSMakeSize(0.0, -1.0)];
		[_insetDropShadow setShadowBlurRadius:3.0];
	}
	return _insetDropShadow;
}

@end
