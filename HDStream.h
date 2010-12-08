/*!
 * HDStream represents a GCD-managed data stream with read and/or write
 * capabilities.
 *
 * @discussion
 * - All operations are thread safe unless otherwise noted.
 * - New streams are suspended by default and need to be resumed before used.
 *
 */
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <libkern/OSAtomic.h>

// Block type for data events
@class HDStream;
typedef void (^HDStreamBlock)(const void *bytes, size_t length);

@interface HDStream : NSObject<NSCopying,NSMutableCopying> {
// sizeof = 384 bytes (including NSObject with its Class pointer, for 64-bit)
@public
  dispatch_queue_t dispatchQueue_;
  uint32_t flags_;
  int fd_;
  
  dispatch_source_t readSource_;
  dispatch_source_t writeSource_;
  HDStreamBlock onData_;
  NSMutableData *readBuffer_;
  OSSpinLock writeSpinLock_;
  struct wbuf *wbufHead_;
  struct wbuf *wbufTail_;
}

// The underlying file descriptor
@property(readonly) int fileDescriptor;

// Test if the stream is suspended. Call suspend and resume to toggle state.
@property(readonly) BOOL isSuspended;

// Test if the stream can be written to
@property(readonly) BOOL isWritable;

// Test if the stream can be read from (if |onData| will be called)
@property(readonly) BOOL isReadable;

// Test if the stream is valid (i.e. valid file descriptor and isn't canceled)
@property(readonly) BOOL isValid;

/*!
 * Called when data arrives on a readable stream.
 *
 * @discussion
 * The buffer returned (|bytes|) is guaranteed to have a size of at least
 * (|length| + 1) which allows you to use that last extra byte for e.g. null
 * termination. Note that |bytes| is only valid within the calling scope -- it
 * will become invalid when the onData block returns, so if you need to keep a
 * reference to the bytes you must make a copy.
 */
@property(copy) HDStreamBlock onData; // (const void *bytes, size_t length)

// The dispatch queue on which this stream should schedule on
@property dispatch_queue_t dispatchQueue;


#pragma mark Creation and Initialization

// A new autoreleased stream of the receiving type
+ (id)stream;

// A new autoreleased stream with |fileDescriptor| of the receiving type
+ (id)streamWithFileDescriptor:(int)fileDescriptor;


// Initialize an empty (and invalid) stream which is useful as placeholder.
- (id)init;

// Initialize the stream with |fileDescriptor| and optionally limiting the mode
- (id)initWithFileDescriptor:(int)fd
              disableReading:(BOOL)disableReading
              disableWriting:(BOOL)disableWriting
               dispatchQueue:(dispatch_queue_t)dispatchQueue;

// Initialize with fd on global normal priority queue
- (id)initWithFileDescriptor:(int)fd;

// Initialize with fd on global normal priority queue with writing disabled
- (id)initWithReadOnlyFileDescriptor:(int)fd;

// Initialize with fd on global normal priority queue with reading disabled
- (id)initWithWriteOnlyFileDescriptor:(int)fd;

#pragma mark State

// Cancel the stream (like close() with traditional I/O)
- (void)cancel;

// Suspend the stream (no-op if already suspended)
- (void)suspend;

// Resume the stream (no-op if not suspended)
- (void)resume;


#pragma mark Deriving new streams

// Create a copy of this stream but with a custom file descriptor
- (HDStream*)copyWithFileDescriptor:(int)fd
                            disableReading:(BOOL)disableReading
                            disableWriting:(BOOL)disableWriting;


#pragma mark Writing

// Write complete |data|
- (void)writeData:(NSData*)data;

// Write |length| bytes from |buffer|
- (void)writeBytes:(const void*)buffer length:(size_t)length;

// Write all |bytes| directly to the stream without buffering
- (void)writeAllUnbufferedBytes:(const void*)bytes length:(size_t)length;

// Write |range| of |string| encoded as |encoding|
- (void)writeString:(NSString*)string
           encoding:(NSStringEncoding)encoding
              range:(NSRange)range;

// Write complete |string| encoded as UTF-8
- (void)writeString:(NSString*)string;

/**
 * Send a file descriptor using sendmsg(2).
 *
 * This will raise NSInvalidArgumentException if the underlying file descriptor
 * does not refer to a UNIX socket.
 *
 * |name| will be encoded as UTF-8 and attached as the first data iovec.
 */
- (BOOL)writeFileDescriptor:(int)fd name:(NSString*)name;


@end

// ----------------------------------------------------------------------------

// A named stream
@interface HDNamedStream : HDStream {
  NSString *name_;
}
@property(retain) NSString *name;
+ (id)streamWithFileDescriptor:(int)fd name:(NSString*)name;
- (id)initWithFileDescriptor:(int)fd name:(NSString*)name;
@end
