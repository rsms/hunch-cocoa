#import "HUImageView.h"
#import "NSShadow+HUAdditions.h"

@implementation HUImageView

@synthesize paths;

- (void)setPath:(NSString *)s {
	paths = [NSArray arrayWithObject:s];
}

- (NSString *)path {
	if (paths && [paths count])
		return [paths objectAtIndex:0];
	return nil;
}

- (void)setImage:(NSImage *)image {
	if (image)
		[image setName:self.path];
	[super setImage:image];
}

- (BOOL)performDragOperation:(id )sender {
	BOOL dragSucceeded = [super performDragOperation:sender];
	if (dragSucceeded) {
		NSString *filenamesXML = [[sender draggingPasteboard] stringForType:NSFilenamesPboardType];
		NSArray *npaths = nil;
		if (filenamesXML) {
			npaths = [NSPropertyListSerialization
														propertyListFromData:[filenamesXML dataUsingEncoding:NSUTF8StringEncoding]
                            mutabilityOption:NSPropertyListImmutable
														format:nil
                            errorDescription:nil];
		}
		paths = npaths;
	}
	return dragSucceeded;
}

@end
