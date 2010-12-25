/*!
 * A URL connection which uses block handlers.
 * 
 * Note: a connection object holds a reference to itself while active which is
 * released after the connection has completed (i.e. you don't need to handle
 * reference counting with respect to the connection lifetime).
 */
@interface HURLConnection : NSURLConnection {
  NSError*(^onResponse_)(NSURLResponse *response);
  NSError*(^onData_)(NSData *data);
  void(^onComplete_)(NSError *err, NSData *data);
  BOOL didRetainSelf_;
}

@property(copy) NSError* (^onResponse)(NSURLResponse *response);
@property(copy) NSError* (^onData)(NSData *data);
@property(copy) void     (^onComplete)(NSError *err, NSData *data);

+ (HURLConnection*)connectionWithRequest:(NSURLRequest*)request
                         onResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                             onDataBlock:(NSError*(^)(NSData *data))onData
                         onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                        startImmediately:(BOOL)startImmediately;

- (id)initWithRequest:(NSURLRequest *)request
      onResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
          onDataBlock:(NSError*(^)(NSData *data))onData
      onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
     startImmediately:(BOOL)startImmediately;

@end


@interface NSURL (blocks)
- (HURLConnection*)fetchWithOnResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                                 onDataBlock:(NSError*(^)(NSData *data))onData
                             onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                            startImmediately:(BOOL)startImmediately;

- (HURLConnection*)fetchWithOnResponseBlock:(NSError*(^)(NSURLResponse *response))onResponse
                             onCompleteBlock:(void(^)(NSError *err, NSData *data))onComplete
                            startImmediately:(BOOL)startImmediately;

@end