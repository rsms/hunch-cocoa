#import "HUInsetTokenFieldCell.h"
#import "HUInsetTokenAttachmentCell.h"

@implementation HUInsetTokenFieldCell

- (id)setUpTokenAttachmentCell:(NSTokenAttachmentCell *)aCell forRepresentedObject:(id)anObj  {
	HUInsetTokenAttachmentCell *attachmentCell = [[HUInsetTokenAttachmentCell alloc] initTextCell:[aCell stringValue]];
	[attachmentCell setRepresentedObject:anObj];
	[attachmentCell setAttachment:[aCell attachment]];
	[attachmentCell setControlSize:[self controlSize]];
	[attachmentCell setTextColor:[NSColor blackColor]];
	[attachmentCell setFont:[self font]];
	return [attachmentCell autorelease];
}

@end
