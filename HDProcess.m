#import <sys/types.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <fcntl.h>

#import <crt_externs.h>
#define environ (*_NSGetEnviron())

#import "HDProcess.h"

// FD utils

static inline BOOL _fd_set_nonblock(int fd) {
  int flags = fcntl(fd, F_GETFL, 0);
  return fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0;
}

static inline BOOL _fd_set_closeonexec(int fd) {
  int flags = fcntl(fd, F_GETFD, 0);
  return fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == 0;
}

static inline BOOL _fd_set_accmode(int fd, int accmode) {
  int fl = fcntl(fd, F_GETFL);
  if (fl == -1) return NO;
  if ((fl & O_ACCMODE) != accmode) {
    return fcntl(fd, F_SETFL, (fl & ~O_ACCMODE) | accmode) == 0;
  }
  return YES;
}

static BOOL _fd_socketpipe(int fd[2]) {
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, fd) != 0)
    return NO;
  // [BUG] this will disable writing, but fcntl will keep a cached value for
  //       O_ACCMODE of F_GETFL which incorrectly reports O_RDWR
  shutdown(fd[0], SHUT_WR);
  fchmod(fd[0], S_IRUSR);
  _fd_set_accmode(fd[0], O_RDONLY);
  // [BUG] this will disable reading, but fcntl will keep a cached value for
  //       O_ACCMODE of F_GETFL which incorrectly reports O_RDWR
  shutdown(fd[1], SHUT_RD);
  fchmod(fd[1], S_IWUSR);
  _fd_set_accmode(fd[1], O_WRONLY);
  errno = 0;
  return YES;
}


static void _proc_handle_ev(HDProcess *self) {
  unsigned long flags = dispatch_source_get_data(self->procSource_);
  /*#define DPFLAG(X) ((flags & DISPATCH_PROC_##X) ? #X" " : "")  
  fprintf(stderr, "process %d: flags: %lx %s%s%s%s\n",
        self.pid, flags,
        DPFLAG(EXIT), DPFLAG(FORK), DPFLAG(EXEC), DPFLAG(SIGNAL));*/
  if (flags & DISPATCH_PROC_EXIT) {
		waitpid(self->pid_, &(self->exitStatus_), WNOHANG);

    // cancel proc source
    dispatch_source_cancel(self->procSource_);
    dispatch_release(self->procSource_);
    self->procSource_ = nil;

    // cancel stdin
    [self->stdinStream_ cancel];

    // cancel channel streams
    for (HDStream *stream in self->channels_) {
      [stream cancel];
    }

    // clear pid
    self->pid_ = -1;

    [self emitEvent:@"exit" argument:self];

    // release proc sources' reference to self
    [self release];
  }
}

// ----------------------------------------------------------------------------

@implementation HDProcess


@synthesize pid = pid_,
            exitStatus = exitStatus_,
            program = program_,
            arguments = arguments_,
            workingDirectory = workingDirectory_,
            environment = environment_,
            stdin = stdinStream_,
            stdout = stdoutStream_,
            stderr = stderrStream_;


/*+ (void)initialize {
  HEventEmitterMixin([self class]);
}*/


+ (HDProcess*)start:(NSString*)program, ... {
  HDProcess *proc = [[HDProcess alloc] init];
  proc.program = program;
	va_list valist;
	va_start(valist, program);
  [proc setVariableArguments:valist];
	va_end(valist);
  return proc;
}

+ (HDProcess*)processWithProgram:(NSString*)program {
  HDProcess *proc = [[self new] autorelease];
  proc.program = program;
  return proc;
}


- (id)init {
  if ((self = [super init])) {
    pid_ = -1;
    dispatchQueue_ =
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    stdinStream_ = [HDStream new];
    stdoutStream_ = [HDStream new];
    stderrStream_ = [HDStream new];
    hasSocketpair_ = YES;
  }
  return self;
}


- (id)initWithProgram:(NSString*)program {
  if ((self = [self init])) {
    self.program = program;
  }
  return self;
}


- (void)dealloc {
  //NSLog(@"%@ dealloc", self);
  // procSource_ should have nil-ed itself at exit, and we should never get here
  // without it being nil since the procSource_ holds a reference to self:
  assert(procSource_ == nil);

  // pid is set to -1 on exit and the exit dispatch source owns a reference to
  // self, so this should always be true:
  assert(pid_ == -1);

  dispatch_release(dispatchQueue_); // no effect if its a global shared queue
  
  [channels_ release];

  [stdinStream_ release];
  [stdoutStream_ release];
  [stderrStream_ release];
  [super dealloc];
}


- (void)setVariableArguments:(va_list)valist {
  NSMutableArray *args = [NSMutableArray array];
  id arg;
  while ((arg = va_arg(valist, id))) {
    [args addObject:arg];
  }
  self.arguments = args;
}


- (BOOL)isRunning {
  return pid_ != -1;
}


- (dispatch_queue_t)dispatchQueue {
  return dispatchQueue_;
}

- (void)setDispatchQueue:(dispatch_queue_t)queue {
  dispatch_queue_t old = dispatchQueue_;
  dispatchQueue_ = queue;
  if (dispatchQueue_) dispatch_retain(dispatchQueue_);
  if (old) dispatch_release(old);
}

- (HDStreamBlock)onStdout { return stdoutStream_.onData; }
- (void)setOnStdout:(HDStreamBlock)block { stdoutStream_.onData = block;}

- (HDStreamBlock)onStderr { return stderrStream_.onData; }
- (void)setOnStderr:(HDStreamBlock)block { stderrStream_.onData = block;}


- (void)startWithArguments:(id)firstArgument, ... {
  if (!firstArgument) {
    self.arguments = nil;
  } else {
    va_list valist;
    va_start(valist, firstArgument);
    [self setVariableArguments:valist];
    va_end(valist);
    // safe since we own the implementation of setVariableArguments:
    NSMutableArray *args = (NSMutableArray*)arguments_;
    [args insertObject:firstArgument atIndex:0];
  }
  [self start];
}


- (void)start {
  // check program
  if (!program_) {
    [NSException raise:NSInvalidArgumentException
                format:@"\"program\" has not been set"];
  }
  
  // check that we are not running
  if (self.isRunning) {
    [NSException raise:NSInternalInconsistencyException
                format:@"already running"];
  }
  
  // reset exist status
  exitStatus_ = -1;
  
  // pipes
  int stdin_pipe[2], stdout_pipe[2], stderr_pipe[2];
  if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
    [NSException raise:NSInternalInconsistencyException
                format:@"pipe(): %s", strerror(errno)];
  }
  
  // stdin (unix socket if usesSocketStdin_ is true, used for FD delegation)
  if (hasSocketpair_) {
    if (!_fd_socketpipe(stdin_pipe)) {
      [NSException raise:NSInternalInconsistencyException
                  format:@"socketpair(): %s", strerror(errno)];
    }
  } else {
    // regular pipe for stdin
    if (pipe(stdin_pipe) < 0) {
      [NSException raise:NSInternalInconsistencyException
                  format:@"pipe(): %s", strerror(errno)];
    }
  }
  
  // set close-on-exec flag
  _fd_set_closeonexec(stdin_pipe[0]);  _fd_set_closeonexec(stdin_pipe[1]);
  _fd_set_closeonexec(stdout_pipe[0]); _fd_set_closeonexec(stdout_pipe[1]);
  _fd_set_closeonexec(stderr_pipe[0]); _fd_set_closeonexec(stderr_pipe[1]);
  
  // save environ in the case that we get it clobbered by the child process.
  char **saved_env = environ;
  
  // vfork & execvp
  pid_ = fork();
  if (pid_ == -1) {
    [NSException raise:NSInternalInconsistencyException format:@"vfork()"];
  } else if (pid_ == 0) {
    // child
    
    // close parent end of pipes and assign our stdio to our end
    close(stdin_pipe[1]);  // close write end
    dup2(stdin_pipe[0],  STDIN_FILENO);
    close(stdout_pipe[0]);  // close read end
    dup2(stdout_pipe[1], STDOUT_FILENO);
    close(stderr_pipe[0]);  // close read end
    dup2(stderr_pipe[1], STDERR_FILENO);
    
    // chdir
    if (workingDirectory_ && chdir([workingDirectory_ UTF8String]) != 0) {
      _exit(127);
    }
    
    // set environment
    if (environment_) {
      NSUInteger envlen = [environment_ count];
      char **envp = (char**)CFAllocatorAllocate(NULL, envlen+1, 0);
      envp[envlen] = NULL;
      int i = 0;
      for (NSString *key in environment_) {
        NSString *value = [environment_ objectForKey:key];
        const char *k = [[key description] UTF8String];
        const char *v = [[value description] UTF8String];
        size_t kz = strlen(k);
        if (kz) {
          size_t z = kz+1+strlen(v)+1;
          char *entry = (char*)CFAllocatorAllocate(NULL, z, 0);
          int z2 = snprintf(entry, z, "%s=%s", k, v);
          envp[i++] = (z2 != -1) ? entry : NULL;
        } else {
          envp[i++] = NULL;
        }
      }
      environ = envp;
    }

    // executable
    const char *file = [program_ UTF8String];
    
    // args
    char *_argv[2] = {NULL, NULL};
    char **argv = (char**)&_argv;
    if (arguments_ && arguments_.count > 0) {
      argv = (char**)malloc(1+arguments_.count+1);
      argv[0] = strdup(file);
      int i = 1;
      for (NSString *arg in arguments_) {
        if (![arg isKindOfClass:[NSString class]])
          arg = [arg description];
        argv[i++] = strdup([arg UTF8String]);
      }
      argv[i] = NULL;
    } else {
      _argv[0] = strdup(file);
    }
    
    // switch process image
    execvp(file, argv);

    // if we get here execvp failed
    _exit(127);
  }
  
  // [parent]

  // restore environment
  environ = saved_env;
  
  // create and start process watcher
  procSource_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid_
                                       ,DISPATCH_PROC_EXIT
                                       //|DISPATCH_PROC_EXEC
                                       //|DISPATCH_PROC_FORK
                                       //|DISPATCH_PROC_SIGNAL
                                       ,dispatchQueue_);
  dispatch_source_set_event_handler_f(procSource_,
                                      (dispatch_function_t)&_proc_handle_ev);
  dispatch_set_context(procSource_, [self retain]); // released by ^
  dispatch_resume(procSource_);
  
  // close other end of pipes
  close(stdin_pipe[0]);//  _fd_set_nonblock(stdin_pipe[1]);
  close(stdout_pipe[1]);// _fd_set_nonblock(stdout_pipe[0]);
  close(stderr_pipe[1]);// _fd_set_nonblock(stderr_pipe[0]);
  
  // explicitly set dispatchQueue_
  stdinStream_.dispatchQueue = dispatchQueue_;
  stdoutStream_.dispatchQueue = dispatchQueue_;
  stderrStream_.dispatchQueue = dispatchQueue_;
  
  // setup and resume stdin, stdout and stderr streams
  HDStream *stdinStream = [stdinStream_
    copyWithFileDescriptor:stdin_pipe[1] disableReading:YES disableWriting:NO];
  HDStream *stdoutStream = [stdoutStream_
    copyWithFileDescriptor:stdout_pipe[0] disableReading:NO disableWriting:YES];
  HDStream *stderrStream = [stderrStream_
    copyWithFileDescriptor:stderr_pipe[0] disableReading:NO disableWriting:YES];
  
  // swap instances
  id old = stdinStream_; stdinStream_ = stdinStream; [old release];
  old = stdoutStream_; stdoutStream_ = stdoutStream; [old release];
  old = stderrStream_; stderrStream_ = stderrStream; [old release];
  
  // make sure they are all in an unsuspended state
  [stdinStream_ resume];
  [stdoutStream_ resume];
  [stderrStream_ resume];
  
  // dequeue any queued input
  if (queuedInput_) {
    for (id entry in queuedInput_) {
      if ([entry isKindOfClass:[NSDictionary class]]) {
        NSNumber *fdn = [entry objectForKey:@"fd"];
        HDNamedStream *channel = [entry objectForKey:@"channel"];
        if (fdn && channel && channel.isValid) {
          // channel file descriptor
          [stdinStream_ writeFileDescriptor:[fdn intValue] name:channel.name];
        }
      }
    }
    [queuedInput_ release];
    queuedInput_ = nil;
  }
}


- (HDNamedStream*)createChannel:(NSString*)name {
  if (!self.isRunning) {
    hasSocketpair_ = YES;
  } else if (!hasSocketpair_) {
    [NSException raise:NSInternalInconsistencyException
                format:@"underlying stdin stream does not support channels"];
  }

  // create a UNIX socket pair (RW,RW)
  int fds[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) {
    [NSException raise:NSInternalInconsistencyException
                format:@"socketpair(): %s", strerror(errno)];
  }

  // create a read+write stream
  HDNamedStream *stream =
      [HDNamedStream streamWithFileDescriptor:fds[0] name:name];
  stream.dispatchQueue = dispatchQueue_;
  
  // register object
  if (!channels_) {
    channels_ = [[NSMutableArray alloc] initWithObjects:stream, nil];
  } else {
    [channels_ addObject:stream];
  }

  // send FD or enqueue
  if (!self.isRunning) {
    // queue the other part of the FD pair to be sent when the process starts
    if (queuedInput_ == nil)
      queuedInput_ = [[NSMutableArray alloc] initWithCapacity:1];
    id entry = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:stream.fileDescriptor], @"fd",
                stream, @"channel", nil];
    [queuedInput_ addObject:entry]; // push back
  } else {
    // send the other part of the FD pair to the process
    [stdinStream_ writeFileDescriptor:fds[1] name:name];
  }
  
  return stream;
}


- (HDNamedStream*)openChannel:(NSString*)name
                              onData:(HDStreamBlock)onData {
  HDNamedStream *stream = [self createChannel:name];
  stream.onData = onData;
  [stream resume];
  return stream;
}


// Send a signal to the process
- (BOOL)sendSignal:(int)signum {
  if (pid_ < 1) {
    return NO;
  } else {
    return kill(pid_, signum) == 0;
  }
}


- (void)terminate {
  [self sendSignal:SIGINT];
}


- (NSString*)description {
  return [NSString stringWithFormat:@"<%@@%p %@ '%@'>",
          NSStringFromClass([self class]), self,
          (pid_ == -1 ? @"-" : [NSString stringWithFormat:@"[%d]", pid_]),
          program_];
}


@end
