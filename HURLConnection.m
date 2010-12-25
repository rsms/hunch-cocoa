#import "HURLConnection.h"

@interface _HURLConnectionDelegate : NSObject {
  NSMutableData *receivedData_;
}
@end
@implementation _HURLConnectionDelegate

- (void)dealloc {
  if (receivedData_) [receivedData_ release];
  [super dealloc];
}

- (void)_onComplete:(HURLConnection*)c error:(NSError*)err cancel:(BOOL)cancel {
  if (cancel)
    [c cancel];
  if (c.onComplete)
    c.onComplete(err, receivedData_);
  [c release];
  [self release];
}

- (void)connection:(HURLConnection*)c didReceiveResponse:(NSURLResponse *)re {
  assert([c isKindOfClass:[HURLConnection class]]);
  if (c.onResponse) {
    NSError *error = c.onResponse(re);
    if (error) [self _onComplete:c error:error cancel:YES];
  }
  if (!c.onData && !receivedData_) {
    receivedData_ = [[NSMutableData alloc] init];
  } else if (receivedData_) {
    [receivedData_ setLength:0];
  }
}

- (void)connection:(HURLConnection *)c didReceiveData:(NSData *)data {
  assert([c isKindOfClass:[HURLConnection class]]);
  if (c.onData) {
    NSError *error = c.onData(data);
    if (error) [self _onComplete:c error:error cancel:YES];
  }
  if (receivedData_)
    [receivedData_ appendData:data];
}

- (void)connection:(HURLConnection *)c didFailWithError:(NSError *)error {
  assert([c isKindOfClass:[HURLConnection class]]);
  [self _onComplete:c error:error cancel:NO];
}

- (void)connectionDidFinishLoading:(HURLConnection *)c {
  assert([c isKindOfClass:[HURLConnection class]]);
  [self _onComplete:c error:nil cancel:NO];
}

@end

// ----------------------------------------------------------------------------

@implementation HURLConnection

@synthesize onResponse = onResponse_,
            onData = onData_,
            onComplete = onComplete_;


+ (HURLConnection*)connectionWithRequest:(NSURLRequest*)request
                         onResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                             onDataBlock:(NSError*(^)(NSData *data))onData
                         onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                        startImmediately:(BOOL)startImmediately {
  HURLConnection *conn = [[self alloc] initWithRequest:request
                                       onResponseBlock:onResponse
                                           onDataBlock:onData
                                       onCompleteBlock:onComplete
                                      startImmediately:startImmediately];
  return [conn autorelease];
}


- (id)initWithRequest:(NSURLRequest *)request
      onResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
          onDataBlock:(NSError*(^)(NSData *data))onData
      onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
     startImmediately:(BOOL)startImmediately {
  self = [super initWithRequest:request
                       delegate:[_HURLConnectionDelegate new]
               startImmediately:startImmediately];
  if (self) {
    if (startImmediately) {
      // see -[start] for discussion on why we do this
      [self retain];
      didRetainSelf_ = YES;
    }
    // set handlers
    self.onResponse = onResponse;
    self.onData = onData;
    self.onComplete = onComplete;
  }
  return self;
}


- (void)start {
  // the _HURLConnectionDelegate sends release to self on complete, so we need
  // to increase the reference count to comply with cocoa connventions (that an
  // object returned from an init method provides a new reference)
  if (!didRetainSelf_) {
    [self retain];
    didRetainSelf_ = YES;
  }
  [super start];
}


- (void)cancel {
  [super cancel];
  if (didRetainSelf_) {
    didRetainSelf_ = NO;
    [self autorelease];
  }
}


- (void)dealloc {
  if (onResponse_) { [onResponse_ release]; onResponse_ = nil; }
  if (onData_) { [onData_ release]; onData_ = nil; }
  if (onComplete_) { [onComplete_ release]; onComplete_ = nil; }
  [super dealloc];
}

@end

// ----------------------------------------------------------------------------

@implementation NSURL (fetch)

- (HURLConnection*)fetchWithOnResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                                onDataBlock:(NSError*(^)(NSData *data))onData
                            onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                           startImmediately:(BOOL)startImmediately {
  NSURLRequest *req = 
      [NSURLRequest requestWithURL:self
                       cachePolicy:NSURLRequestUseProtocolCachePolicy
                   timeoutInterval:60.0];
  return [HURLConnection connectionWithRequest:req
                               onResponseBlock:onResponse
                                   onDataBlock:onData
                               onCompleteBlock:onComplete
                              startImmediately:startImmediately];
}

- (HURLConnection*)fetchWithOnResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                            onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                           startImmediately:(BOOL)startImmediately {
  return [self fetchWithOnResponseBlock:onResponse
                            onDataBlock:nil
                        onCompleteBlock:onComplete
                       startImmediately:startImmediately];
}

@end