#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

#import "HDStream.h"
#import "HEventEmitter.h"
@class HDProcess;

// Block type for process events
typedef void (^HDProcessBlock)(HDProcess *process);

/*!
 * Subprocess facility based on Grand Central Dispatch.
 *
 * Events emitted:
 *
 * - "exit" (HDProcess *self) -- the process exited
 *
 * Example:
 *
 *    #import "HDProcess.h"
 *    HDProcess *process = [HDProcess processWithProgram:@"enscript"];
 *    process.stdout.onData = ^(const void *bytes, size_t length) {
 *      // do something with stdout data hunk
 *    };
 *    process.stderr.onData = ^(const void *bytes, size_t length) {
 *      // do something with stderr data hunk
 *    };
 *    [process on:@"exit", ^(HDProcess *process){
 *      NSLog(@"exit code: %d", process.exitStatus);
 *    }];
 *    [process startWithArguments:@"--foo", @"bar", nil];
 *
 */
@interface HDProcess : NSObject {
 @public
  NSString *program_;
  NSArray *arguments_;
  NSString *workingDirectory_;
  NSDictionary *environment_;

  dispatch_source_t procSource_;

  HDStream *stdinStream_;
  HDStream *stdoutStream_;
  HDStream *stderrStream_;
  NSMutableArray *channels_;

  dispatch_queue_t dispatchQueue_;
  pid_t pid_;
  int exitStatus_;
  BOOL hasSocketpair_;
  NSMutableArray *queuedInput_;
}

/**
 * Name or path of executable.
 *
 * - If |program| does not contain a "/", the environment PATH will be searched
 *   just like in a shell.
 *
 * - If no executable header could be found in the referenced file, a shell
 *   will be used to try to execute the program (i.e. execute a script).
 *
 */
@property(retain) NSString *program;

// Optional arguments passed to |program| when started
@property(retain) NSArray *arguments;
- (void)setVariableArguments:(va_list)valist;

// Optional custom working directory. Defaults to the current working directory
@property(retain) NSString *workingDirectory;

/**
 * Optional custom environment. Defaults to the current environment.
 *
 * To extend the environment rather than set it, you can fetch the current
 * environment and patch it using NSProcessInfo:
 *
 *    NSDictionary *currentEnv = [[NSProcessInfo processInfo] environment];
 *    NSMutableDictionary *env = [currentEnv mutableCopy];
 *    [env setObject:@"/foo/bar/bin" forKey:@"PATH"];
 *
 */
@property(retain) NSDictionary *environment;


// Process identifier of the process, or -1 if not running
@property(readonly) pid_t pid;

// The exit status of a terminated process
@property(readonly) int exitStatus;

// True if the process is running
@property(readonly) BOOL isRunning;


/**
 * Dispatch queue to schedule events on. By default the normal priority, global
 * concurrent queue is used.
 *
 * Note that stream callbacks (onStd*, channels, etc) are guaranteed to be
 * called serially (i.e. they are not reentrant).
 */
@property dispatch_queue_t dispatchQueue;

// Interface to the process' standard input (writable stream)
@property(readonly) HDStream *stdin;

// Interface to the process' standard output (readable stream)
@property(readonly) HDStream *stdout;

// Interface to the process' standard error (readable stream)
@property(readonly) HDStream *stderr;


// Note: Callbacks might be called on background threads

// Optional callback invoked when data arrives from the process' standard output
@property(copy) HDStreamBlock onStdout;

// Optional callback invoked when data arrives from the process' standard error
@property(copy) HDStreamBlock onStderr;


// New autoreleased process with |program|
+ (HDProcess*)processWithProgram:(NSString*)program;

// Launch a process with optional arguments (nil-terminated)
+ (HDProcess*)start:(NSString*)program, ... __attribute__((sentinel));

// Initialize with |program|
- (id)initWithProgram:(NSString*)program;

// Launch the process
- (void)start;

// Launch the process, setting |arguments| from nil-terminated argument list.
- (void)startWithArguments:(id)firstArgument, ... __attribute__((sentinel));

// Terminate the process (sends signal 2 aka SIGINT aka interrupt)
- (void)terminate;

// Send a signal to the process. Returns true on success.
- (BOOL)sendSignal:(int)signum;

/**
 * Create a new bidirectional channel.
 *
 * This works by setting up a pair of read+write UNIX stream sockets using
 * socketpair(2). The first file descriptor is will be kept by us, the other one
 * is send to the process' standard input using sendmsg(2) together with |name|.
 *
 * The process should perform the following at start up:
 *
 *   1. recvmsg(2) on its stdin file descriptor
 *   2. Locate (cmsg_type == SCM_RIGHTS) and parse the data as a file descriptor
 *   3. Register that file descriptor as a new channel to the host process
 *
 *   -  Optionally msg_iov[0] can be parsed as UTF-8 text data (value of |name|)
 *      to decide on what to do with a certain file descriptor
 *
 * Requirements:
 *
 *   1. The process must be started
 *   2. |enableChannels| was set to YES before the process was started
 *   3. The process must use recvmsg(2) on its stdin file descriptor to accept
 *      and use a sent file descriptor
 *
 * This method will raise an NSInternalInconsistencyException if any of
 * requirements 1-2 are not met.
 *
 * Example node.js echo program:
 *
 *    var net = require("net");
 *    var stdin = new net.Stream(0, 'unix');
 *    stdin.on('fd', function (fd) {
 *      var stream = new net.Stream(fd, "unix");
 *      stream.resume();
 *      stream.on('data', function (message) {
 *        stream.write('pong '+message.toString('utf8'));
 *      });
 *    });
 *    stdin.resume();
 *
 * Example Cocoa snippet to go with the above node.js program:
 *
 *    HDProcess *process ... // configure process
 *    process.enableChannels = YES;
 *    [proc start];
 *    [proc openChannel:@"parent"
 *    onData:^(HDStream *s, const void *bytes, size_t length){
 *      if (length == 0) return; // EOS
 *      printf("channel.onData -> %*s\n", length, (const char*)bytes);
 *    }];
 *
 * The returned HDStream is autoreleased, but will remain valid until
 * the channel is closed (A reference is managed by its dispatch queue). Note
 * that the returned stream pair is in a suspended state and need to receive a
 * "resume" message to actually start processing input.
 */
- (HDNamedStream*)createChannel:(NSString*)name;


/**
 * Convenience method wrapping up the following boiler plate:
 *
 *    HDNamedStream *channel = [proc createChannel:name];
 *    channel.onData = onData;
 *    [channel resume];
 *
 */
- (HDNamedStream*)openChannel:(NSString*)name onData:(HDStreamBlock)onData;

@end
