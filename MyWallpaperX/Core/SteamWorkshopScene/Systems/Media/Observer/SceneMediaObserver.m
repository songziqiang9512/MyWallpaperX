// Project-authored experimental platform adapter. Loaded by the system Perl
// host, then entered through its public XS ABI after dlopen has returned.
// Never execute a run loop from a dylib initializer: artwork decoding may load
// ImageIO plugins on a worker while the loader's initializer lock is held.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>

static const NSUInteger MWXMaximumArtworkBytes = 16 * 1024 * 1024;
static const NSUInteger MWXMaximumTextBytes = 4096;

static BOOL MWXSignature(id target, SEL selector, const char *result, const char *argument) {
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == (argument ? 3 : 2)
        && strcmp(signature.methodReturnType, result) == 0
        && (!argument || strcmp([signature getArgumentTypeAtIndex:2], argument) == 0);
}
static id MWXObject(id target, const char *name) {
    SEL selector = sel_registerName(name);
    if (!MWXSignature(target, selector, "@", NULL)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}
static BOOL MWXSetObject(id target, const char *name, id value) {
    SEL selector = sel_registerName(name);
    if (!MWXSignature(target, selector, "v", "@")) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    return YES;
}
static BOOL MWXSetDouble(id target, const char *name, double value) {
    SEL selector = sel_registerName(name);
    if (!MWXSignature(target, selector, "v", "d")) return NO;
    ((void (*)(id, SEL, double))objc_msgSend)(target, selector, value);
    return YES;
}
static BOOL MWXSetBool(id target, const char *name, BOOL value) {
    SEL selector = sel_registerName(name);
    if (!MWXSignature(target, selector, "v", "B")) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(target, selector, value);
    return YES;
}
static BOOL MWXAction(id target, const char *name) {
    SEL selector = sel_registerName(name);
    if (!MWXSignature(target, selector, "v", NULL)) return NO;
    ((void (*)(id, SEL))objc_msgSend)(target, selector);
    return YES;
}
static NSString *MWXString(id value) {
    if (![value isKindOfClass:NSString.class]
        || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > MWXMaximumTextBytes
        || [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    return value;
}
static NSDictionary *MWXInfo(id item) {
    id value = MWXObject(item, "nowPlayingInfo");
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static double MWXNumber(id value) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return 0;
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 ? number : 0;
}
static NSString *MWXSource(id playerPath) {
    return MWXString(MWXObject(MWXObject(playerPath, "client"), "bundleIdentifier"));
}
static BOOL MWXWrite(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!data || data.length > 24 * 1024 * 1024) return NO;
    return fwrite(data.bytes, 1, data.length, stdout) == data.length
        && fputc('\n', stdout) != EOF && fflush(stdout) == 0;
}

@interface MWXMediaObserver : NSObject
@property(nonatomic, strong) id controller;
@property(nonatomic, copy) NSString *source;
@property(nonatomic, copy) NSString *identity;
@property(nonatomic, copy) NSString *artworkIdentity;
@property(nonatomic, copy) id playerPath;
@property(nonatomic, copy) NSData *artworkData;
@end

@implementation MWXMediaObserver
- (BOOL)begin {
    Class controllerType = NSClassFromString(@"MRNowPlayingController");
    self.controller = MWXObject(controllerType, "localRouteController");
    id configuration = MWXObject(self.controller, "configuration");
    id request = MWXObject(NSClassFromString(@"MRPlaybackQueueRequest"), "defaultPlaybackQueueRequest");
    return request && MWXSetDouble(request, "setArtworkWidth:", 512)
        && MWXSetDouble(request, "setArtworkHeight:", 512)
        && MWXSetObject(configuration, "setPlaybackQueueRequest:", request)
        && MWXSetBool(configuration, "setRequestPlaybackQueue:", YES)
        && MWXSetBool(configuration, "setRequestPlaybackState:", YES)
        && MWXSetObject(self.controller, "setConfiguration:", configuration)
        && MWXAction(self.controller, "beginLoadingUpdates");
}
- (void)clearIdentity {
    self.source = nil;
    self.identity = nil;
    self.artworkIdentity = nil;
    self.playerPath = nil;
    self.artworkData = nil;
}
- (NSDictionary *)empty:(NSString *)status {
    [self clearIdentity];
    return @{ @"version": @1, @"status": status };
}
- (NSDictionary *)snapshot {
    Class requestType = NSClassFromString(@"MRNowPlayingRequest");
    id path = MWXObject(requestType, "localNowPlayingPlayerPath");
    NSString *source = MWXSource(path);
    NSString *identity = MWXString(MWXInfo(MWXObject(requestType, "localNowPlayingItem"))[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]);
    if (!source.length) return [self empty:@"noSession"];
    if (!identity.length) return [self empty:@"unavailable"];
    BOOL running = NO;
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:source]) {
        if (!app.terminated) { running = YES; break; }
    }
    if (!running) return [self empty:@"noSession"];
    id response = MWXObject(self.controller, "response");
    id responsePath = MWXObject(response, "playerPath");
    if (![path isEqual:responsePath]) return [self empty:@"unavailable"];
    id queue = MWXObject(response, "playbackQueue");
    id items = MWXObject(queue, "contentItems");
    if (![items isKindOfClass:NSArray.class]) return [self empty:@"unavailable"];
    id current = nil;
    for (id item in items) {
        if ([MWXString(MWXObject(item, "identifier")) isEqualToString:identity]) { current = item; break; }
    }
    if (!current) return [self empty:@"unavailable"];
    NSDictionary *info = MWXInfo(current);
    if (![MWXString(info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]) isEqualToString:identity]) return [self empty:@"unavailable"];
    SEL playingSelector = sel_registerName("localIsPlaying");
    if (!MWXSignature(requestType, playingSelector, "B", NULL)) return [self empty:@"unavailable"];
    BOOL playing = ((BOOL (*)(id, SEL))objc_msgSend)(requestType, playingSelector);
    double duration = MWXNumber(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    double position = MWXNumber(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    if (playing && [timestamp isKindOfClass:NSDate.class]) {
        double elapsed = -[timestamp timeIntervalSinceNow];
        double rate = MWXNumber(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
        if (isfinite(elapsed) && elapsed > 0) position += elapsed * rate;
    }
    if (!isfinite(position)) position = 0;
    if (duration > 0) position = MIN(position, duration);
    NSString *artworkIdentity = MWXString(info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]) ?: @"";
    BOOL sameTrack = [self.playerPath isEqual:path]
        && [self.source isEqualToString:source] && [self.identity isEqualToString:identity];
    BOOL sameArtwork = sameTrack && [self.artworkIdentity isEqualToString:artworkIdentity];
    BOOL artworkChanged = !sameArtwork;
    NSData *artwork = sameArtwork ? self.artworkData : nil;
    // A missing artwork identifier cannot prove that the bytes are unchanged.
    // Compare at the input polling rate, never in the Scene frame loop.
    if (!sameArtwork || !artworkIdentity.length || !self.artworkData) {
        artwork = nil;
        id value = MWXObject(MWXObject(current, "artwork"), "imageData");
        if ([value isKindOfClass:NSData.class] && [value length] > 0 && [value length] <= MWXMaximumArtworkBytes) {
            CGImageSourceRef image = CGImageSourceCreateWithData((__bridge CFDataRef)value, NULL);
            if (image) {
                NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(image, 0, NULL));
                double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
                double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
                if (width > 0 && height > 0 && width <= 8192 && height <= 8192 && width * height <= 16777216) artwork = value;
                CFRelease(image);
            }
        }
    }
    artworkChanged = artworkChanged || !(artwork == self.artworkData
        || [artwork isEqualToData:self.artworkData]);
    // The controller's response and the current-source shortcut update separately.
    // Drop this sample if either identity moved while extracting optional artwork.
    id afterPath = MWXObject(requestType, "localNowPlayingPlayerPath");
    NSString *afterSource = MWXSource(afterPath);
    NSString *afterIdentity = MWXString(MWXInfo(MWXObject(requestType, "localNowPlayingItem"))[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]);
    if (![path isEqual:afterPath] || ![source isEqualToString:afterSource]
        || ![identity isEqualToString:afterIdentity]) return [self empty:@"unavailable"];
    NSMutableDictionary *result = [@{ @"version": @1, @"status": @"snapshot", @"source": source,
        @"identity": identity, @"title": MWXString(info[@"kMRMediaRemoteNowPlayingInfoTitle"]) ?: @"",
        @"artist": MWXString(info[@"kMRMediaRemoteNowPlayingInfoArtist"]) ?: @"",
        @"album": MWXString(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]) ?: @"",
        @"playbackState": playing ? @1 : @2, @"position": @(position), @"duration": @(duration),
        @"artworkIdentifier": artworkIdentity, @"artworkChanged": @(artworkChanged) } mutableCopy];
    if (artworkChanged && artwork) result[@"artworkData"] = [artwork base64EncodedStringWithOptions:0];
    self.source = source;
    self.playerPath = path;
    self.identity = identity;
    self.artworkIdentity = artworkIdentity;
    self.artworkData = artwork;
    return result;
}
@end

static void MWXRun(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (![[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"] load]) {
            MWXWrite(@{ @"version": @1, @"status": @"unavailable" });
            return;
        }
        MWXMediaObserver *observer = [MWXMediaObserver new];
        if (![observer begin]) { MWXWrite([observer empty:@"unavailable"]); return; }
        // The parent owns demand, timeout, restart and termination. This process
        // performs no player commands and no persistent file/cache writes.
        for (;;) {
            @autoreleasepool {
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
                NSDictionary *snapshot;
                @try { snapshot = [observer snapshot]; }
                @catch (NSException *exception) { snapshot = [observer empty:@"unavailable"]; }
                if (!MWXWrite(snapshot)) break;
            }
        }
        MWXAction(observer.controller, "endLoadingUpdates");
    }
}

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
XS(mwx_scene_media_run) { dXSARGS; MWXRun(); XSRETURN_EMPTY; }
