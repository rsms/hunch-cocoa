#import "HUWebServiceProxy.h"
#import "JSON.h"

@implementation HUWebServiceProxy

#pragma mark -
#pragma mark Preparing requests

- (NSURL *)urlForMethod:(NSString *)m withArgs:(id)args {
	@throw [NSException exceptionWithName:@"NotImplementedError" reason:@"The urlForMethod:withArgs: method is not implemented" userInfo:[NSDictionary dictionaryWithObject:self forKey:@"target"]];
	return nil;
}

- (BOOL)willSendRequest:(ASIHTTPRequest *)r toMethod:(NSString *)method withArgs:(id)args {
	if (args)
		r.postBody = [[[args JSONRepresentation] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
	return YES;
}

#pragma mark -
#pragma mark Handling responses

- (BOOL)responseIsError:(ASIHTTPRequest *)r {
	if (r.responseStatusCode < 200 || r.responseStatusCode >= 300) {
		r.error = [NSError errorWithDomain:NetworkRequestErrorDomain code:0 userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Non-200 response: %d %@\n%@", r.responseStatusCode, r.responseStatusMessage, [r responseString]] forKey:NSLocalizedDescriptionKey]];
		return YES;
	}
	return NO;
}

- (NSObject *)parsedObjectFromResponse:(ASIHTTPRequest *)r withContentType:(NSString *)type {
	if ([type isEqualToString:@"application/json"]) {
		return [[r responseString] JSONValue];
	}
	return nil;
}

- (void)requestFinished:(ASIHTTPRequest *)r withParsedObject:(NSObject *)obj {
	HUWebServiceProxyCallBlock block;
	if (r.userInfo && (block = [r.userInfo objectForKey:@"block"])) {
		block(obj, nil);
		[block release];
	}
}

- (void)requestFailed:(ASIHTTPRequest *)r {
	HUWebServiceProxyCallBlock block;
	if (r.userInfo && (block = [r.userInfo objectForKey:@"block"])) {
		block(r, r.error);
		[block release];
	}
}


// --------------------
#pragma mark -
#pragma mark Base

- (void)requestFinished:(ASIHTTPRequest *)r {
	NSString *contentType = nil;
	NSObject *parsedObject = nil;
	
	// check if response is error and if so continue with requestFailed:
	if ([self responseIsError:r]) {
		[self requestFailed:r];
		return;
	}
	
	// todo: case-insensitive search for "content-type"
	if (!(contentType = [r.responseHeaders objectForKey:@"Content-Type"]))
		contentType = [r.responseHeaders objectForKey:@"Content-type"];
	
	// parse response object if possible
	if (r.contentLength) {
		if (contentType) {
			NSRange range = [contentType rangeOfString:@";"];
			if (range.location != NSNotFound) {
				contentType = [[contentType substringToIndex:range.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			}
		}
		parsedObject = [self parsedObjectFromResponse:r withContentType:contentType];
	}
	
	// xxx debug logging:
	#if DEBUG
	NSLog(@"debug: %@ request finished: %d %@ (type=%@, method=%@) <%u bytes>", 
				self, r.responseStatusCode, r.responseStatusMessage, contentType, 
				[r.userInfo objectForKey:@"method"], r.contentLength);
	NSLog(@"debug: parsedObject %@", parsedObject);
	#endif
	
	// Possibly modify parsedObject and call block if allowed and appropriate
	[self requestFinished:r withParsedObject:parsedObject];
}


- (ASIHTTPRequest *)call:(NSString *)method, ... {
	va_list ap;
	va_start(ap, method);
	id arg = nil, args = nil;
	HUWebServiceProxyCallBlock block = nil;
	
	while(1) {
		if (!(arg = va_arg(ap, id)))
			break;
		if (![arg isKindOfClass:[NSDictionary class]]) {
			// && [[NSString stringWithFormat:@"%@", arg] rangeOfString:@"__NSAutoBlock__"].location != NSNotFound // not workz :(
			block = arg;
			break;
		}
		else {
			args = arg;
		}
	}
	va_end(ap);
	return [self call:method args:args block:block autostart:YES];
}


- (ASIHTTPRequest *)call:(NSString *)method block:(HUWebServiceProxyCallBlock)b {
	return [self call:method args:nil block:b autostart:YES];
}


- (ASIHTTPRequest *)call:(NSString *)method args:(id)args block:(HUWebServiceProxyCallBlock)b {
	return [self call:method args:args block:b autostart:YES];
}


- (ASIHTTPRequest *)call:(NSString *)method args:(id)args block:(HUWebServiceProxyCallBlock)cl autostart:(BOOL)start
{
	NSURL *url = [self urlForMethod:method withArgs:args];
	ASIHTTPRequest *r = [ASIHTTPRequest requestWithURL:url];
	[r setDelegate:self];
	
	if (cl)
		cl = [cl copy]; // todo: check if it's already copied?
	
	if (args && cl) {
		r.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									method, @"method", args, @"args", cl, @"block", nil];
	}
	else if (args) {
		r.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									method, @"method", args, @"args", nil];
	}
	else if (cl) {
		r.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
									method, @"method", cl, @"block", nil];
	}
	else {
		r.userInfo = [NSDictionary dictionaryWithObject:method forKey:@"method"];
	}
	
	if ([self willSendRequest:r toMethod:method withArgs:args]) {
		if (start)
			[r startAsynchronous];
		return r;
	}
	// else aborted
	
	if (cl)
		[cl release];
	return nil;
}

@end
