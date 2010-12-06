#import "HDStream.h"
#import <libkern/OSAtomic.h>
#import <fcntl.h>
#import <sys/socket.h>

#import <sys/stat.h>

/*
 TODO: suspend read source while there is no onData listener
*/

// ----------------------------------------------------------------------------
// flags

enum { // [0-31]
  kFlagSuspended = 0,
  kFlagSuspendedWrite,
  kFlagReadable,
  kFlagWritable,
};

// types are: volatile uint32_t *flags, uint32_t flag

// Set |flag| in |flags| unless already set. Returns true if set.
#define HAFLAG_SET(flags, flag) !OSAtomicTestAndSetBarrier(flag, flags)

// Clear |flag| in |flags| if set. Returns false if |flag| was not set (no-op).
#define HAFLAG_CLEAR(flags, flag) OSAtomicTestAndClearBarrier(flag, flags)

// Test if |flag| is set in |flags|. True if set.
#define HAFLAG_TEST(flags, flag) \
  (!!(  ( *((char*)(flags)+((flag) >> 3)) ) & (0x80 >> ((flag) & 7))  ))


// instance-local macros
#define FLAG_SET(flag) HAFLAG_SET(&flags_, flag)
#define FLAG_CLEAR(flag) HAFLAG_CLEAR(&flags_, flag)
#define FLAG_TEST(flag) HAFLAG_TEST(&flags_, flag)

// ----------------------------------------------------------------------------
// Write buffer chain

typedef struct wbuf {
  struct wbuf *next; // a more recent buffer (closer to wbufHead_)
  NSData *data;
  size_t offset;
} wbuf_t;

// ----------------------------------------------------------------------------


static void _read(HDStream *self) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  void *buf = NULL;
  ssize_t length = 0;
  
  assert(self->readSource_);
	size_t estimatedSize = dispatch_source_get_data(self->readSource_);
  if (estimatedSize == 0) {
    // EOF
    dispatch_source_cancel(self->readSource_);
    goto invoke_on_data_and_return;
  }
  
  // read buffer (safe since reads as serial)
  if (!self->readBuffer_) {
    self->readBuffer_ = [[NSMutableData alloc] initWithCapacity:estimatedSize];
  } else {
    // increase buffer size if needed
    if (self->readBuffer_.length < estimatedSize)
      [self->readBuffer_ setLength:estimatedSize];
  }
  
  int fd = dispatch_source_get_handle(self->readSource_);
  buf = [self->readBuffer_ mutableBytes];
  length = read(fd, buf, estimatedSize);
  if (length == -1) {
    if (errno != EAGAIN) {
      NSLog(@"%@: read(): [%d] %s -- closing the file descriptor", self, errno,
            strerror(errno));
      dispatch_source_cancel(self->readSource_);
		}
  } else {
    #if 0  // debug
    ((char*)buf)[length] = '\0';
    printf("Estimated bytes available: %ld -- actual: %ld '%s'\n",
           estimatedSize, length, (char*)buf);
    #endif
invoke_on_data_and_return:
    //printf("%d DID READ \"%*s\"\n",
    //       dispatch_source_get_handle(self->readSource_), length, buf);
    if (self->onData_) {
      @try {
        self->onData_(buf, length);
      } @catch (NSException * e) {
        NSLog(@"%@: exception while invoking callback: %@", self, e);
      }
    }
  }
  
  [pool drain];
}


static void _read_finalize(HDStream *self) {
  int fd = dispatch_source_get_handle(self->readSource_);
  close(fd);
  dispatch_release(self->readSource_);
  self->readSource_ = nil;
  self->fd_ = -1;
  [self release];
}


static void _write(HDStream *self) {
  //#define ldprintf printf // local debug printf
  #define ldprintf(...) ((void)0)
  int fd = dispatch_source_get_handle(self->writeSource_);
  ldprintf("write: available %ld\n",
           dispatch_source_get_data(self->writeSource_));
  
  // write all chained buffers. break on empty input or full output
  //
  // Note: You might think that writev(2) would be a better solution here, but
  //       writev actually copies all buffers to a temporary new buffer which
  //       is then sent (and thus copied) to the kernel and finally free'd.
  //       Performance gains are negligable in most cases and even negative in
  //       some situations.
  //
  while (1) {
    // get oldest wbuf_t
    // Note: no need for locking here since we are the only ones dealing with
    //       the tail
    assert(self->wbufTail_ != NULL);
    wbuf_t *wbuf = self->wbufTail_;

    // local ref to buffer
    const char *buf = (const char*)[wbuf->data bytes];
    size_t buflen = [wbuf->data length];
    size_t len = buflen - wbuf->offset;

    // write
    ssize_t written = write(fd, &buf[wbuf->offset], len);
    ldprintf("write(%d, %p (+%lu), %lu) -> %lu\n", fd, &buf[wbuf->offset],
             wbuf->offset, len, written);
    
    // handle result
    if (written < 0) {
      ldprintf("write() error: [%d] %s", errno, strerror(errno));
      switch (errno) {
        // try-again "errors":
        case EINTR:  // write syscall interrupted
        case EAGAIN: // fd temporarily unavailable
          goto _write__after_while_loop;

        // Gracefully cancel the source, closing fd:
        case EBADF:  // Bad file descriptor
        case EPIPE:  // Broken pipe
        case EIO:    // Generic input/output error
          // FD has been shutdown() or disconnected -- gracefully cancel without
          // an error message
          break;

        // Other errors are considered serious and are logged
        default:
          NSLog(@"%@: write(): [%d] %s -- closing the file descriptor", self,
                errno, strerror(errno));
      }
      dispatch_source_cancel(self->writeSource_);
      break;
    } else if (written < len) {
      // there's still data on this buffer that need to be written
      wbuf->offset += written;
      ldprintf("write: advanced offset of same buffer\n");
      break; // output buffer is full -- hold our horses
    } else {
      // buffer emptied
      OSSpinLockLock(&(self->writeSpinLock_));
      if (wbuf->next == NULL) {
        // we where the last link in the chain
        self->wbufTail_ = self->wbufHead_ = NULL;
        // suspend write source until needed
        if (HAFLAG_SET(&(self->flags_), kFlagSuspendedWrite))
          dispatch_suspend(self->writeSource_);
        ldprintf("write: suspended due to empty buffer\n");
      } else {
        // there are more buffers in the chain
        self->wbufTail_ = wbuf->next;
        ldprintf("write: advanced to next buffer\n");
      }
      // discard used buffer
      [wbuf->data release];
      CFAllocatorDeallocate(NULL, wbuf);
      
      OSSpinLockUnlock(&(self->writeSpinLock_));
      
      // break if input is empty
      if (self->wbufTail_ == NULL)
        break;
    }
  }
  // reserved for future finalization -- we always get here before returning
  _write__after_while_loop:
  return;
  #undef ldprintf
}


static void _write_finalize(HDStream *self) {
  int fd = dispatch_source_get_handle(self->writeSource_);
  close(fd);
  dispatch_release(self->writeSource_);
  self->writeSource_ = nil;
  self->fd_ = -1;
  [self release];
}


// ----------------------------------------------------------------------------

@interface HDStream (Private)
- (void)_createReadSource;
- (void)_createWriteSource;
@end
@implementation HDStream (Private)

- (void)_createReadSource {
  assert(readSource_ == nil);
  assert(dispatchQueue_ != nil);

  // create source
  readSource_ =
      dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd_, 0, dispatchQueue_);
  assert(readSource_ != NULL);
  dispatch_source_set_event_handler_f(readSource_, (dispatch_function_t)&_read);
  dispatch_source_set_cancel_handler_f(readSource_,
                                       (dispatch_function_t)&_read_finalize);
  dispatch_set_context(readSource_, [self retain]); // released by ^
}


- (void)_createWriteSource {
  // Note: writeSource_ will NOT be nil here, but rather 0x1 because of how we
  //       have solved atomicity. Calls to this method are never the subject to
  //       a race condition (managed from the outside).

  // create source
  writeSource_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd_, 0,
                                        dispatchQueue_);
  assert(writeSource_ != NULL);
  dispatch_source_set_event_handler_f(writeSource_,
                                      (dispatch_function_t)&_write);
  dispatch_source_set_cancel_handler_f(writeSource_,
                                       (dispatch_function_t)&_write_finalize);
  dispatch_set_context(writeSource_, [self retain]); // released by ^
}


@end

// ----------------------------------------------------------------------------

@implementation HDStream

@synthesize onData = onData_;


#pragma mark Creation and Initialization


+ (id)stream {
  return [[self new] autorelease];
}


+ (id)streamWithFileDescriptor:(int)fileDescriptor {
  HDStream *stream = [self alloc]; // to avoid "Multiple medods..." warn
  return [[stream initWithFileDescriptor:fileDescriptor] autorelease];
}


- (id)init {
  if ((self = [super init])) {
    fd_ = -1;
    FLAG_SET(kFlagSuspended);
    writeSpinLock_ = OS_SPINLOCK_INIT;
    dispatchQueue_ =
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  }
  return self;
}


- (id)initWithFileDescriptor:(int)fd
              disableReading:(BOOL)disableReading
              disableWriting:(BOOL)disableWriting
               dispatchQueue:(dispatch_queue_t)dispatchQueue {
  if (!(self = [self init])) return self;
  fd_ = fd;

  // set non-blocking flag if needed
  int flags = fcntl(fd, F_GETFD, 0);
  if ((flags == -1) || (
       (flags & O_NONBLOCK) != O_NONBLOCK &&
        fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) ) {
    [NSException raise:NSInvalidArgumentException format:@"%s",strerror(errno)];
  }

  // get file mode
  // |readable| and |writable| can restrict mode, but not enable it
  int mode = fcntl(fd, F_GETFL);
  if (mode == -1)
    [NSException raise:NSInvalidArgumentException format:@"%s",strerror(errno)];
  mode = mode & O_ACCMODE;
  if (mode == O_RDONLY) {
    disableReading ? FLAG_CLEAR(kFlagReadable) : FLAG_SET(kFlagReadable);
    FLAG_CLEAR(kFlagWritable);
  } else if (mode == O_WRONLY) {
    FLAG_CLEAR(kFlagReadable);
    disableWriting ? FLAG_CLEAR(kFlagWritable) : FLAG_SET(kFlagWritable);
  } else if (mode == O_RDWR) {
    disableReading ? FLAG_CLEAR(kFlagReadable) : FLAG_SET(kFlagReadable);
    disableWriting ? FLAG_CLEAR(kFlagWritable) : FLAG_SET(kFlagWritable);
  }

  // set queue
  dispatchQueue_ = dispatchQueue ? dispatchQueue :
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  // setup read source
  if (FLAG_TEST(kFlagReadable))
    [self _createReadSource];
  
  // future: setup write source
  
  return self;
}


- (id)initWithFileDescriptor:(int)fd {
  return [self initWithFileDescriptor:fd disableReading:NO disableWriting:NO
                        dispatchQueue:nil];
}

// Initialize with fd on global normal priority queue with writing disabled
- (id)initWithReadOnlyFileDescriptor:(int)fd {
  return [self initWithFileDescriptor:fd disableReading:NO disableWriting:YES
                        dispatchQueue:nil];
}

// Initialize with fd on global normal priority queue with reading disabled
- (id)initWithWriteOnlyFileDescriptor:(int)fd {
  return [self initWithFileDescriptor:fd disableReading:YES disableWriting:NO
                        dispatchQueue:nil];
}


- (void)dealloc {
  if (onData_) [onData_ release];
  if (readBuffer_) [readBuffer_ release];
  if (readSource_) {
    dispatch_release(readSource_);
    readSource_ = nil;
  }
  if (dispatchQueue_) {
    dispatch_release(dispatchQueue_);
    dispatchQueue_ = nil;
  }
  [super dealloc];
}


#pragma mark Properties


- (int)fileDescriptor {
  if (readSource_)
    return dispatch_source_get_handle(readSource_);
  return -1;
}


- (BOOL)isSuspended { return FLAG_TEST(kFlagSuspended); }
- (BOOL)isWritable { return FLAG_TEST(kFlagWritable); }
- (BOOL)isReadable { return FLAG_TEST(kFlagReadable); }

- (BOOL)isValid {
  if ( (fd_ == -1) ||
       (readSource_ && dispatch_source_testcancel(readSource_) != 0) ) {
    return NO;
  }
  return self.isReadable || self.isWritable;
}


- (dispatch_queue_t)dispatchQueue { return dispatchQueue_; }

- (void)setDispatchQueue:(dispatch_queue_t)dispatchQueue {
  OSMemoryBarrier();
  dispatch_queue_t old = dispatchQueue_;
  dispatchQueue_ = dispatchQueue;
  if (dispatchQueue_) {
    dispatch_retain(dispatchQueue_);
  } else {
    dispatchQueue_ =
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  }
  if (readSource_) dispatch_set_target_queue(readSource_, dispatchQueue_);
  if (writeSource_) dispatch_set_target_queue(writeSource_, dispatchQueue_);
  if (old) dispatch_release(old);
}


#pragma mark State


- (void)cancel {
  if (readSource_) dispatch_source_cancel(readSource_);
  if (writeSource_) dispatch_source_cancel(writeSource_);
  // need to resume or will never cancel
  [self resume];
}

- (void)suspend {
  if (FLAG_SET(kFlagSuspended))
    if (readSource_) dispatch_suspend(readSource_);
  if (FLAG_SET(kFlagSuspendedWrite))
    if (writeSource_) dispatch_suspend(writeSource_);
}

- (void)resume {
  if (FLAG_CLEAR(kFlagSuspended))
    if (readSource_) dispatch_resume(readSource_);
  if (FLAG_CLEAR(kFlagSuspendedWrite))
    if (writeSource_) dispatch_resume(writeSource_);
}


#pragma mark Deriving new streams


- (HDStream*)copyWithFileDescriptor:(int)fd
                            disableReading:(BOOL)disableReading
                            disableWriting:(BOOL)disableWriting {
  HDStream *stream =
    [[isa alloc] initWithFileDescriptor:fd disableReading:disableReading
                  disableWriting:disableWriting dispatchQueue:dispatchQueue_];
  if (onData_)
    stream.onData = onData_;
  if (!self.isSuspended)
    [stream resume];
  return stream;
}


// NSMutableCopying protocol
- (id)mutableCopyWithZone:(NSZone *)zone {
  return [[isa allocWithZone:zone] initWithFileDescriptor:fd_
                                           disableReading:!self.isReadable
                                           disableWriting:!self.isWritable
                                            dispatchQueue:dispatchQueue_];
}

// NSCopying protocol
- (id)copyWithZone:(NSZone *)zone {
  return [self mutableCopyWithZone:zone];
}


#pragma mark Writing


- (void)writeData:(NSData*)data {
  wbuf_t *wbuf = CFAllocatorAllocate(NULL, sizeof(wbuf_t), 0);
  wbuf->data = [data retain];
  wbuf->next = NULL;
  wbuf->offset = 0;
  
  OSSpinLockLock(&writeSpinLock_);
  if (wbufHead_) {
    // there's already a buffer chain -- push_front
    wbufHead_->next = wbuf;
    wbufHead_ = wbuf;
  } else {
    // first link in chain
    wbufHead_ = wbuf;
    wbufTail_ = wbuf;
  }

  // create write source if needed
  if (!writeSource_) {
    [self _createWriteSource];
    OSSpinLockUnlock(&writeSpinLock_);
    if (!FLAG_TEST(kFlagSuspended)) {
      dispatch_resume(writeSource_);
    } else {
      // important to balance resume/suspend calls, so record writer state
      FLAG_SET(kFlagSuspendedWrite);
    }
  } else {
    OSSpinLockUnlock(&writeSpinLock_);
    if (!FLAG_TEST(kFlagSuspended) && FLAG_CLEAR(kFlagSuspendedWrite)) {
      // we are not explicitly suspended, but the writer was suspended due to
      // empty buffer, but we now have a buffer so resume it
      dispatch_resume(writeSource_);
    }
  }
}


- (void)writeBytes:(const void*)bytes length:(size_t)length {
  if (!length) return;
  [self writeData:[NSData dataWithBytes:bytes length:length]];
}


- (void)writeAllUnbufferedBytes:(const void*)bytes length:(size_t)length {
  ssize_t bw, totalbw = 0;
  do {
    bw = write(fd_, (void*)((char*)bytes+totalbw), length-totalbw);
    if (bw < 0) {
      if (errno == EINTR || errno == EAGAIN) {
        continue;
      } else {
        [NSException raise:NSInternalInconsistencyException
                    format:@"write(): %s", strerror(errno)];
        return;
      }
    }
    totalbw += bw;
  } while (totalbw < length);
}


- (void)writeString:(NSString*)str
           encoding:(NSStringEncoding)encoding
              range:(NSRange)range {
  NSUInteger estimatedSize = [str maximumLengthOfBytesUsingEncoding:encoding];
  char *buf = (char*)CFAllocatorAllocate(NULL, estimatedSize*sizeof(char), 0);
  NSUInteger actualSize = 0;
  [str getBytes:buf
      maxLength:estimatedSize
     usedLength:&actualSize
       encoding:encoding
        options:0
          range:range
  remainingRange:NULL];
  NSData *data = [NSData dataWithBytesNoCopy:buf
                                      length:actualSize
                                freeWhenDone:YES];
  [self writeData:data];
}


- (void)writeString:(NSString*)str {
  [self writeData:[str dataUsingEncoding:NSUTF8StringEncoding]];
}


// This will raise NSInvalidArgumentException if the underlying file descriptor
// does not refer to a UNIX socket.
- (BOOL)writeFileDescriptor:(int)fd name:(NSString*)name {
  struct iovec iov;
  const char *buffer_data = name ? [name UTF8String] : NULL;
  size_t buffer_length = buffer_data ? strlen(buffer_data) : 0;
  size_t offset = 0;
  size_t length = buffer_length - offset;
  
  iov.iov_base = (void*)(buffer_data + offset);
  iov.iov_len = length;
  
  int flags = 0;
  
  struct msghdr msg;
  char scratch[64];
  
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_name = NULL;
  msg.msg_namelen = 0;
  msg.msg_flags = 0;
  msg.msg_control = NULL;
  msg.msg_controllen = 0;
  
  struct cmsghdr *cmsg;
  
  msg.msg_control = (void*)scratch;
  msg.msg_controllen = CMSG_LEN(sizeof(fd));
  
  cmsg = CMSG_FIRSTHDR(&msg);
  cmsg->cmsg_level = SOL_SOCKET;
  cmsg->cmsg_type = SCM_RIGHTS;
  cmsg->cmsg_len = msg.msg_controllen;
  *(int*)CMSG_DATA(cmsg) = fd;
  
  ssize_t written = sendmsg(fd_, &msg, flags);
  
  if (written < 0) {
    if (errno == EAGAIN || errno == EINTR)
      return YES;
    [NSException raise:NSInvalidArgumentException
                format:@"sendmsg(): %s", strerror(errno)];
  }
  
  return NO;
}


#pragma mark -
#pragma mark Etc

- (NSString*)description {
  if (fd_ != -1) {
    NSString *rw = @"-";
    if (self.isReadable && self.isWritable) rw = @"R+W";
    else if (self.isReadable) rw = @"R";
    else if (self.isWritable) rw = @"W";
    return [NSString stringWithFormat:@"<%@@%p %@ %@>",
            NSStringFromClass([self class]), self,
            [NSString stringWithFormat:@"%d", fd_], rw];
  } else {
    return [NSString stringWithFormat:@"<%@@%p>",
        NSStringFromClass([self class]), self];
  }
}


@end

// ----------------------------------------------------------------------------

@implementation HDNamedStream
@synthesize name = name_;

+ (id)streamWithFileDescriptor:(int)fd name:(NSString*)name {
  HDNamedStream *stream = [self streamWithFileDescriptor:fd];
  if (stream) stream.name = name;
  return stream;
}

- (id)initWithFileDescriptor:(int)fd name:(NSString*)name {
  if ((self = [super initWithFileDescriptor:fd])) {
    self.name = name;
  }
  return self;
}

@end
