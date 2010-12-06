#import "HDProcess.h"
#import "HRefcountLogger.h"

static NSString *tempNSString(const void *bytes, size_t length) {
  return [[[NSString alloc] initWithBytesNoCopy:(void*)bytes length:length
                                       encoding:NSISOLatin1StringEncoding
                                   freeWhenDone:NO] autorelease];
}


int main (int argc, const char * argv[]) {  
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  
  // Not everyone has /usr/local/bin in their path, which is the default
  // location of node
  setenv("PATH", [[[NSString stringWithUTF8String:getenv("PATH")]
                   stringByAppendingString:@":/usr/local/bin"] UTF8String], 1);


  // Setup a new process running the "node" program
  HDProcess *proc = [HDProcess processWithProgram:@"node"];
  HRefcountLogger *rlogger = [[HRefcountLogger new] autorelease];
  [proc on:@"exit", ^(HDProcess *self){
    [rlogger noop];
    NSLog(@"%@ exited with status %d", self, self.exitStatus);
    // since this is a simple demo and we are "trapped" in a never-returning
    // runloop, in the name of pragmatism, we die w/o caring about finalization
    dispatch_after(dispatch_time(0, 1000*1000000LL), self.dispatchQueue, ^{
      _exit(0);
    });
  }];
  proc.onStdout = ^(const void *bytes, size_t length){
    if (length == 0) return; // End of Stream
    // should not decode strings ad-hoc -- this is just for dev/demo
    NSLog(@"onStdout -> '%@'", tempNSString(bytes, length));
  };
  proc.onStderr = ^(const void *bytes, size_t length){
    if (length == 0) return; // End of Stream
    // Note: this is just for demo purposes -- bytes might not be valid text:
    NSLog(@"onStderr -> '%@'", tempNSString(bytes, length));
  };
  [proc startWithArguments:@"../../examples/fd-receiver.js", nil];
  [proc on:@"exit", ^(id self){
    NSLog(@"event handler for \"exit\" event on %@ invoked", self);
  }];

  // Open a channel
  HDStream *channel = [proc openChannel:@"parent"
  onData:^(const void *bytes, size_t length){
    if (length == 0) return; // End of Stream
    // Note: this is just for demo purposes -- bytes might not be valid text:
    NSLog(@"channel.onData -> '%@'", tempNSString(bytes, length));
  }];
  NSLog(@"created channel %@", channel);
  [channel writeString:@"hello!"];
  [channel writeString:@"hello!"];
  
  // write some data to process' stdin after a short delay (600ms)
  dispatch_time_t delay = dispatch_time(0, 600*1000000LL);
  dispatch_queue_t queue =
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_after(delay, queue, ^{
    if (proc.isRunning && proc.stdinStream.isValid)
      [proc.stdinStream writeString:@"exit"];
  });
  
  // enter never-returning runloop
  [pool drain];
  dispatch_main();
  assert(0); // should never get here
  
  return 0;
}
