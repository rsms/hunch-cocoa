#import "ASIHTTPRequest.h"

/**
 * Call closure.
 *
 * When a call fails, <error> will be a non-nil value and <parsedResponseObject>
 * will be the ASIHTTPRequest object. Otherwise <error> will be nil.
 *
 * Example:
 *
 *     [someService call:@"some.method", ^(id r, NSError *err){
 *       if (err) {
 *         NSLog(@"call %@ failed with error %@", r, err);
 *       }
 *       else {
 *         NSLog(@"some.method returned: %@", r);
 *       }
 *     }];
 *
 */
typedef void (^HUWebServiceProxyCallClosure)(id parsedResponseObject, NSError *error);


@interface HUWebServiceProxy : NSObject {
}

#pragma mark -
#pragma mark Preparing requests

/**
 * Return the URL which should be used to make a call to <method> with <args>.
 *
 * The default implementation will throw an exception -- you must override
 * this method.
 */
- (NSURL *)urlForMethod:(NSString *)method withArgs:(id)args;

/**
 * Called before a request will be sent.
 *
 * In most cases, this is where you set r.postBody based on <method> and <args>.
 *
 * Returning a false value results in the request being aborted and -call:*
 * methods returning nil.
 *
 * The default implementation sets r.postBody to the JSON representation of
 * <args> which also implicitly converts the request to a POST request. Nothing
 * is done if <args> is nil.
 */
- (BOOL)willSendRequest:(ASIHTTPRequest *)r toMethod:(NSString *)method withArgs:(id)args;


#pragma mark -
#pragma mark Handling responses
/*
 Call order:

 -requestFinished:
   -responseIsError:
     (might switch branch to -requestFailed:)
   -parsedObjectFromResponse:withContentType:
   -requestFinished:withParsedObject:
   closure(parsedObject, nil)

 -requestFailed:
   -requestFailed:withError:
   closure(nil, error)
*/

/**
 * Return a true value and set/modify <error> if the response is considered
 * to be an error.
 *
 * If a true value is returned, requestFailed: will be called isntead of
 * requestFinished:. <error> will be available through r.error;
 *
 * The default implementation will consider a response to be an error if the
 * responseStatusCode is less than 200 or greater than 299.
 */
- (BOOL)responseIsError:(ASIHTTPRequest *)r;

/**
 * Return an object which is the representation of the response.
 * Might return nil to indicate the response is not parsable.
 *
 * Called after a complete response has been received.
 *
 * The object returned will later be passed to requestFinished:withParsedObject:
 * which might manipulate the object further. The object is then passed to
 * the response closure, if any.
 *
 * The default implementation tries to parse the object based on content type.
 */
- (NSObject *)parsedObjectFromResponse:(ASIHTTPRequest *)r withContentType:(NSString *)ct;

/**
 * Called when a request has successfully finished.
 *
 * The default implementation calls closure(msg, nil) and releases the closure
 * after it returns.
 */
- (void)requestFinished:(ASIHTTPRequest *)request withParsedObject:(NSObject *)msg;

/**
 * Called when a request has failed.
 *
 * The default implementation calls closure(r, r.error) and releases the closure
 * after it returns.
 */
- (void)requestFailed:(ASIHTTPRequest *)r;


#pragma mark -
#pragma mark Calling remote methods

/**
 * Call a remote method by variadic convenience.
 *
 * Exactly one closure must be specified.
 *
 * Example:
 *
 *     [someService call:@"some.method", ^(id r, NSError *err){
 *       // ...
 *     }];
 *
 * Example with arguments:
 *
 *     NSDictionary *args = [NSDictionary dictionaryWithObject:@"rasmus" forKey:@"name"];
 *     [someService call:@"some.method", args, ^(id r, NSError *err){
 *       // ...
 *     }];
 */
- (ASIHTTPRequest *)call:(NSString *)method, ...;

/**
 * Call a remote method and dispatch the call immediately.
 */
-(ASIHTTPRequest *)call:(NSString *)method
									 args:(id)args
								closure:(HUWebServiceProxyCallClosure)b;

/**
 * Call a remote method without any arguments and dispatch the call immediately.
 */
-(ASIHTTPRequest *)call:(NSString *)method
								closure:(HUWebServiceProxyCallClosure)b;

/**
 * Call a remote method.
 *
 * If <autostart> is true, the call is dispatched immediately, otherwise the caller is
 * responsible for calling startAsynchronous (or start for synchronous calls -- not
 * recommended) on the returned request object.
 */
-(ASIHTTPRequest *)call:(NSString *)method
									 args:(id)args
								closure:(HUWebServiceProxyCallClosure)b
							autostart:(BOOL)autostart;

#pragma mark -
#pragma mark Base

- (void)requestFinished:(ASIHTTPRequest *)request;

@end
