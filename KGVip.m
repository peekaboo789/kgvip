#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <objc/runtime.h>

// Concept-edition account (official free VIP). Token rotates: refresh by rerunning the login flow.
static NSString *const kKGToken = @"8ddc87a8426cfc97059d50f6efe27e81a40c25e25ab6dc21f671e109d4da32a7d4070591a7bff89b32923194bd506e8b560d9778515848d31a927e08c76417f20076e8b4d449c1262c8866f883f7444e";
static const long long kKGUserid = 1621039645;
static const long long kKGAppId = 1005;
static const long long kKGClientVer = 11040;
static NSString *const kKGSaltSign = @"OIlwieks28dk2k092lksi2UIkp";
static NSString *const kKGSaltKey = @"57ae12eb6890223e355ccfcb74edf70d";
static NSString *const kKGVipHandled = @"KGVipHandled";

static NSString *KGMD5(NSString *input) {
    if (!input) input = @"";
    const char *cstr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cstr, (CC_LONG)strlen(cstr), digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

static NSString *KGScalarString(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    if (!v) return @"";
    return [v description];
}

static NSString *KGSignKey(NSString *hash, NSString *mid, long long userid, long long appid) {
    return KGMD5([NSString stringWithFormat:@"%@%@%lld%@%lld",
                  [hash lowercaseString], kKGSaltKey, appid, mid ?: @"-", userid]);
}

static NSString *KGSign(NSDictionary *params, NSString *data) {
    NSArray *keys = [[params allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *joined = [NSMutableString string];
    for (NSString *key in keys) {
        [joined appendFormat:@"%@=%@", key, KGScalarString(params[key])];
    }
    return KGMD5([NSString stringWithFormat:@"%@%@%@%@", kKGSaltSign, joined, data ?: @"", kKGSaltSign]);
}

static NSString *KGQueryValue(NSURL *url, NSString *name) {
    NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in comp.queryItems) {
        if ([item.name isEqualToString:name]) return item.value ?: @"";
    }
    return nil;
}

@interface KGVipProtocol : NSURLProtocol
@end

@implementation KGVipProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kKGVipHandled inRequest:request]) return NO;
    NSString *raw = request.URL.absoluteString;
    if (!raw) return NO;
    NSString *lower = [raw lowercaseString];
    if (![lower containsString:@"/v3/url"] && ![lower containsString:@"/v5/url"]) return NO;
    return YES;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)stopLoading {}

- (void)startLoading {
    NSURLRequest *original = self.request;
    NSString *hash = KGQueryValue(original.URL, @"hash") ?: @"";
    NSString *quality = KGQueryValue(original.URL, @"quality") ?: @"128";
    NSString *albumAudioId = KGQueryValue(original.URL, @"album_audio_id") ?: @"0";
    NSString *albumId = KGQueryValue(original.URL, @"album_id") ?: @"0";

    if (hash.length == 0) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:@"KGVip" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"empty hash"}]];
        return;
    }

    NSString *dfid = @"-";
    NSString *mid = KGMD5(dfid);
    NSString *uuid = KGMD5([NSString stringWithFormat:@"%@%@", dfid, mid]);
    long long clienttime = (long long)[[NSDate date] timeIntervalSince1970];

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"album_id"] = @([albumId longLongValue]);
    params[@"area_code"] = @1;
    params[@"hash"] = [hash lowercaseString];
    params[@"ssa_flag"] = @"is_fromtrack";
    params[@"version"] = @11040;
    params[@"page_id"] = @151369488;
    params[@"quality"] = quality;
    params[@"album_audio_id"] = @([albumAudioId longLongValue]);
    params[@"behavior"] = @"play";
    params[@"pid"] = @2;
    params[@"cmd"] = @26;
    params[@"pidversion"] = @3001;
    params[@"IsFreePart"] = @0;
    params[@"ppage_id"] = @"463467626,350369493,788954147";
    params[@"cdnBackup"] = @1;
    params[@"kcard"] = @0;
    params[@"module"] = @"";
    params[@"dfid"] = dfid;
    params[@"mid"] = mid;
    params[@"uuid"] = uuid;
    params[@"appid"] = @(kKGAppId);
    params[@"clientver"] = @(kKGClientVer);
    params[@"userid"] = @(kKGUserid);
    params[@"clienttime"] = @(clienttime);
    params[@"token"] = kKGToken;
    params[@"key"] = KGSignKey(hash, mid, kKGUserid, kKGAppId);
    params[@"signature"] = KGSign(params, @"");

    NSURLComponents *v5 = [NSURLComponents componentsWithString:@"https://gateway.kugou.com/v5/url"];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in params) {
        [items addObject:[NSURLQueryItem queryItemWithName:key value:KGScalarString(params[key])]];
    }
    v5.queryItems = items;

    NSMutableURLRequest *v5req = [NSMutableURLRequest requestWithURL:v5.URL];
    [v5req setValue:@"trackercdn.kugou.com" forHTTPHeaderField:@"x-router"];
    [v5req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [NSURLProtocol setProperty:@YES forKey:kKGVipHandled inRequest:v5req];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:v5req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSData *body = data ?: [NSData data];

        id parsed = nil;
        @try { parsed = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL]; } @catch (NSException *e) { parsed = nil; }

        NSInteger status = http ? http.statusCode : 200;
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)parsed;
            id st = d[@"status"];
            if (st) status = [st integerValue];
        }

        NSMutableDictionary *reply = [NSMutableDictionary dictionary];
        reply[@"status"] = @(status == 0 ? 1 : status);
        if ([parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)parsed;
            if (d[@"url"] && d[@"url"] != [NSNull null]) reply[@"url"] = d[@"url"];
            if (d[@"backup_url"] && d[@"backup_url"] != [NSNull null]) reply[@"backup_url"] = d[@"backup_url"];
            if (d[@"fileSize"]) reply[@"fileSize"] = d[@"fileSize"];
            if (d[@"timeLength"]) reply[@"timeLength"] = d[@"timeLength"];
            if (d[@"fileHash"]) reply[@"fileHash"] = d[@"fileHash"];
            reply[@"IsFreePart"] = @0;
            if (!reply[@"url"] && d[@"data"] && d[@"data"] != [NSNull null]) {
                reply[@"url"] = d[@"data"];
            }
        }

        NSInteger headerStatus = http ? http.statusCode : 200;
        NSString *reason = [NSHTTPURLResponse localizedStringForStatusCode:headerStatus];
        NSHTTPURLResponse *out = [[NSHTTPURLResponse alloc] initWithURL:original.URL
                                                            statusCode:headerStatus
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:@{@"Content-Type": @"application/json", @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length]}];
        (void)reason;

        [self.client URLProtocol:self didReceiveResponse:out cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        NSData *outData = [NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL] ?: body;
        [self.client URLProtocol:self didLoadData:outData];
        [self.client URLProtocolDidFinishLoading:self];
    }];
    [task resume];
}

@end

static void KGSwizzleClassMethod(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getClassMethod(cls, original);
    Method m2 = class_getClassMethod(cls, replacement);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

@interface NSURLSession (KGVipHook)
@end

@implementation NSURLSession (KGVipHook)

+ (NSURLSession *)kgvip_sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                        delegate:(id)delegate
                                   delegateQueue:(NSOperationQueue *)queue {
    if (configuration) {
        NSMutableArray *classes = [NSMutableArray arrayWithObject:[KGVipProtocol class]];
        for (Class c in configuration.protocolClasses) {
            if (c != [KGVipProtocol class]) [classes addObject:c];
        }
        configuration.protocolClasses = classes;
    }
    return [self kgvip_sessionWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

- (instancetype)kgvip_initWithConfiguration:(NSURLSessionConfiguration *)configuration
                                   delegate:(id)delegate
                              delegateQueue:(NSOperationQueue *)queue {
    if (configuration) {
        NSMutableArray *classes = [NSMutableArray arrayWithObject:[KGVipProtocol class]];
        for (Class c in configuration.protocolClasses) {
            if (c != [KGVipProtocol class]) [classes addObject:c];
        }
        configuration.protocolClasses = classes;
    }
    return [self kgvip_initWithConfiguration:configuration delegate:delegate delegateQueue:queue];
}

static void KGSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method m1 = class_getInstanceMethod(cls, original);
    Method m2 = class_getInstanceMethod(cls, replacement);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        KGSwizzleClassMethod([NSURLSession class],
                             @selector(sessionWithConfiguration:delegate:delegateQueue:),
                             @selector(kgvip_sessionWithConfiguration:delegate:delegateQueue:));
        KGSwizzleInstanceMethod([NSURLSession class],
                                @selector(initWithConfiguration:delegate:delegateQueue:),
                                @selector(kgvip_initWithConfiguration:delegate:delegateQueue:));
        [NSURLProtocol registerClass:[KGVipProtocol class]];
    });
}

@end
