#!/usr/bin/env python3
"""Call the real observer snapshot with owned runtime objects and generated PNGs."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Systems/Media/Observer/SceneMediaObserver.m"

HARNESS = r'''
#include "SceneMediaObserver.m"

static id localPath, localItem, afterPath, afterItem;
static BOOL hasRunningApp = YES, appTerminated = NO;
static _Bool isPlaying = YES;
static BOOL changeWhileReading = NO;
static NSUInteger artworkReads = 0;

@interface OwnedClient : NSObject
@property(nonatomic, strong) id bundleIdentifier;
@end
@implementation OwnedClient @end

@interface OwnedPath : NSObject <NSCopying>
@property(nonatomic, strong) OwnedClient *client;
@property(nonatomic, copy) NSString *route;
@end
@implementation OwnedPath
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:OwnedPath.class]
        && [self.client.bundleIdentifier isEqual:((OwnedPath *)other).client.bundleIdentifier]
        && [self.route isEqualToString:((OwnedPath *)other).route];
}
- (NSUInteger)hash { return [self.client.bundleIdentifier hash] ^ self.route.hash; }
@end

@interface OwnedArtwork : NSObject
@property(nonatomic, strong) id bytes;
@end
@implementation OwnedArtwork
- (id)imageData {
    artworkReads++;
    if (changeWhileReading) {
        localPath = afterPath;
        localItem = afterItem;
        changeWhileReading = NO;
    }
    return self.bytes;
}
@end

@interface OwnedWrongSignatureArtwork : NSObject @end
@implementation OwnedWrongSignatureArtwork
- (NSInteger)imageData { abort(); }
@end

@interface OwnedItem : NSObject
@property(nonatomic, strong) id identifier;
@property(nonatomic, strong) id nowPlayingInfo;
@property(nonatomic, strong) id artwork;
@end
@implementation OwnedItem @end

@interface OwnedQueue : NSObject
@property(nonatomic, strong) id contentItems;
@end
@implementation OwnedQueue @end

@interface OwnedResponse : NSObject
@property(nonatomic, strong) id playerPath;
@property(nonatomic, strong) OwnedQueue *playbackQueue;
@end
@implementation OwnedResponse @end

@interface OwnedController : NSObject
@property(nonatomic, strong) OwnedResponse *response;
@end
@implementation OwnedController @end

// These classes exist only in this CPU executable. MWXRun is never entered,
// so no system MediaRemote framework or real player query is involved.
@interface MRNowPlayingRequest : NSObject
+ (id)localNowPlayingPlayerPath;
+ (id)localNowPlayingItem;
+ (_Bool)localIsPlaying;
+ (BOOL)ownedFixtureIdentity;
@end
@implementation MRNowPlayingRequest
+ (id)localNowPlayingPlayerPath { return localPath; }
+ (id)localNowPlayingItem { return localItem; }
+ (_Bool)localIsPlaying { return isPlaying; }
+ (BOOL)ownedFixtureIdentity { return YES; }
@end

@interface OwnedRunningApplication : NSObject @end
@implementation OwnedRunningApplication
- (BOOL)isTerminated { return appTerminated; }
@end

static NSArray *ownedRunningApplications(id target, SEL selector, NSString *source) {
    return hasRunningApp ? @[[OwnedRunningApplication new]] : @[];
}
static NSUInteger checks;
static void check(BOOL condition) { if (!condition) abort(); checks++; }
static void status(NSDictionary *value, NSString *expected) {
    check([value[@"status"] isEqualToString:expected]);
}
static OwnedPath *path(NSString *source, NSString *route) {
    OwnedPath *value = [OwnedPath new];
    value.client = [OwnedClient new]; value.client.bundleIdentifier = source; value.route = route;
    return value;
}
static NSMutableDictionary *info(NSString *identity) {
    NSMutableDictionary *value = [@{ @"kMRMediaRemoteNowPlayingInfoTitle": @"Owned title",
        @"kMRMediaRemoteNowPlayingInfoArtist": @"Owned artist", @"kMRMediaRemoteNowPlayingInfoAlbum": @"Owned album",
        @"kMRMediaRemoteNowPlayingInfoDuration": @180, @"kMRMediaRemoteNowPlayingInfoElapsedTime": @3,
        @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier": @"artA" } mutableCopy];
    if (identity) value[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] = identity;
    return value;
}
static OwnedItem *item(NSString *identity, NSData *bytes) {
    OwnedItem *value = [OwnedItem new]; value.identifier = identity;
    value.nowPlayingInfo = info(identity);
    OwnedArtwork *art = [OwnedArtwork new]; art.bytes = bytes; value.artwork = art;
    return value;
}
static NSData *png(NSUInteger width, uint8_t red, uint8_t green) {
    NSMutableData *pixels = [NSMutableData dataWithLength:width * 4];
    uint8_t *bytes = pixels.mutableBytes;
    for (NSUInteger x = 0; x < width; x++) {
        bytes[x * 4] = red; bytes[x * 4 + 1] = green; bytes[x * 4 + 3] = 255;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(bytes, width, 1, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    check(context != NULL);
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,
        CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    check(CGImageDestinationFinalize(destination));
    CFRelease(destination); CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(space);
    return data;
}
static MWXMediaObserver *fixture(NSData *bytes) {
    hasRunningApp = YES; appTerminated = NO; isPlaying = YES;
    changeWhileReading = NO; artworkReads = 0;
    localPath = path(@"owned.source.A", @"route.A"); localItem = item(@"same.content", bytes);
    OwnedQueue *queue = [OwnedQueue new]; queue.contentItems = @[item(@"same.content", bytes)];
    OwnedResponse *response = [OwnedResponse new]; response.playerPath = localPath; response.playbackQueue = queue;
    OwnedController *controller = [OwnedController new]; controller.response = response;
    MWXMediaObserver *observer = [MWXMediaObserver new]; observer.controller = controller;
    return observer;
}
static OwnedItem *current(MWXMediaObserver *observer) {
    return [[[(OwnedController *)observer.controller response] playbackQueue] contentItems][0];
}
static OwnedResponse *response(MWXMediaObserver *observer) { return [(OwnedController *)observer.controller response]; }
static NSData *artwork(NSDictionary *snapshot) {
    id encoded = snapshot[@"artworkData"];
    return encoded ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
}
static void cleared(MWXMediaObserver *observer) {
    check(observer.source == nil && observer.identity == nil && observer.playerPath == nil);
    check(observer.artworkIdentity == nil && observer.artworkData == nil);
}

static void identities(NSData *a) {
    MWXMediaObserver *observer = fixture(a);
    status([observer snapshot], @"snapshot");
    response(observer).playerPath = path(@"owned.source.B", @"route.A");
    status([observer snapshot], @"unavailable"); cleared(observer);
    observer = fixture(a);
    response(observer).playerPath = path(@"owned.source.A", @"route.B");
    status([observer snapshot], @"unavailable"); cleared(observer);
    observer = fixture(a);
    [(NSMutableDictionary *)[localItem nowPlayingInfo] removeObjectForKey:@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"];
    status([observer snapshot], @"unavailable"); cleared(observer);
    observer = fixture(a);
    current(observer).nowPlayingInfo = info(@"different.content");
    status([observer snapshot], @"unavailable");
    observer = fixture(a);
    current(observer).identifier = @"different.content";
    status([observer snapshot], @"unavailable");
    observer = fixture(a);
    response(observer).playbackQueue.contentItems = NSNull.null;
    status([observer snapshot], @"unavailable");
    observer = fixture(a); appTerminated = YES;
    status([observer snapshot], @"noSession"); cleared(observer);
    observer = fixture(a); hasRunningApp = NO;
    status([observer snapshot], @"noSession");
    observer = fixture(a); localPath = nil;
    status([observer snapshot], @"noSession");
}

static void whileReading(NSData *a) {
    for (NSUInteger mode = 0; mode < 3; mode++) {
        MWXMediaObserver *observer = fixture(a);
        afterPath = mode == 0 ? path(@"owned.source.B", @"route.A")
            : mode == 1 ? path(@"owned.source.A", @"route.B") : localPath;
        afterItem = mode == 2 ? item(@"new.content", a) : localItem;
        changeWhileReading = YES;
        status([observer snapshot], @"unavailable");
        check(artworkReads == 1); cleared(observer);
    }
}

static void noArtworkIdentifier(NSData *a, NSData *b) {
    MWXMediaObserver *observer = fixture(a);
    [(NSMutableDictionary *)current(observer).nowPlayingInfo removeObjectForKey:@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
    NSDictionary *one = [observer snapshot]; status(one, @"snapshot");
    check([one[@"artworkChanged"] boolValue] && [artwork(one) isEqualToData:a]);
    NSDictionary *same = [observer snapshot]; status(same, @"snapshot");
    check(![same[@"artworkChanged"] boolValue] && same[@"artworkData"] == nil);
    [(OwnedArtwork *)current(observer).artwork setBytes:b];
    NSDictionary *two = [observer snapshot]; status(two, @"snapshot");
    check([two[@"artworkChanged"] boolValue] && [artwork(two) isEqualToData:b]);
    same = [observer snapshot];
    check(![same[@"artworkChanged"] boolValue] && same[@"artworkData"] == nil);
    [(OwnedArtwork *)current(observer).artwork setBytes:nil];
    NSDictionary *clear = [observer snapshot]; status(clear, @"snapshot");
    check([clear[@"artworkChanged"] boolValue] && clear[@"artworkData"] == nil && observer.artworkData == nil);
    same = [observer snapshot];
    check(![same[@"artworkChanged"] boolValue] && same[@"artworkData"] == nil);
    check(artworkReads == 6);
}

static void bounds(NSData *a) {
    MWXMediaObserver *observer = fixture(a);
    NSMutableDictionary *metadata = current(observer).nowPlayingInfo;
    metadata[@"kMRMediaRemoteNowPlayingInfoTitle"] = [@"x" stringByPaddingToLength:4097 withString:@"x" startingAtIndex:0];
    metadata[@"kMRMediaRemoteNowPlayingInfoArtist"] = @"bad\nartist";
    metadata[@"kMRMediaRemoteNowPlayingInfoAlbum"] = @1;
    metadata[@"kMRMediaRemoteNowPlayingInfoDuration"] = @YES;
    metadata[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] = @(-2);
    NSDictionary *value = [observer snapshot]; status(value, @"snapshot");
    check([value[@"title"] isEqualToString:@""] && [value[@"artist"] isEqualToString:@""] && [value[@"album"] isEqualToString:@""]);
    check([value[@"position"] doubleValue] == 0 && [value[@"duration"] doubleValue] == 0);
    check([artwork(value) isEqualToData:a]);
    observer = fixture(a); isPlaying = NO;
    metadata = current(observer).nowPlayingInfo;
    metadata[@"kMRMediaRemoteNowPlayingInfoTimestamp"] = [NSDate dateWithTimeIntervalSinceNow:-100];
    metadata[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] = @1;
    value = [observer snapshot];
    check([value[@"playbackState"] integerValue] == 2 && [value[@"position"] doubleValue] == 3);
    observer = fixture(a);
    current(observer).artwork = [OwnedWrongSignatureArtwork new];
    value = [observer snapshot]; status(value, @"snapshot");
    check([value[@"artworkChanged"] boolValue] && value[@"artworkData"] == nil);
    check([value[@"title"] isEqualToString:@"Owned title"]);
    for (id invalid in @[[NSData dataWithBytes:"invalid" length:7],
                         [NSMutableData dataWithLength:MWXMaximumArtworkBytes + 1], png(8193, 255, 0), NSNull.null]) {
        observer = fixture(a); status([observer snapshot], @"snapshot");
        metadata = current(observer).nowPlayingInfo;
        metadata[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] = @"new.art";
        [(OwnedArtwork *)current(observer).artwork setBytes:invalid];
        value = [observer snapshot]; status(value, @"snapshot");
        check([value[@"artworkChanged"] boolValue] && value[@"artworkData"] == nil && observer.artworkData == nil);
        check([value[@"title"] isEqualToString:@"Owned title"]);
    }
    NSData *edge = png(8192, 255, 0);
    observer = fixture(edge); value = [observer snapshot]; status(value, @"snapshot");
    check([artwork(value) isEqualToData:edge]);
    observer = fixture(a); status([observer snapshot], @"snapshot");
    localPath = path(@"owned.source.B", @"route.A"); response(observer).playerPath = localPath;
    value = [observer snapshot]; status(value, @"snapshot");
    check([value[@"source"] isEqualToString:@"owned.source.B"] && [value[@"artworkChanged"] boolValue]);
    check([artwork(value) isEqualToData:a] && artworkReads == 2);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        check([NSClassFromString(@"MRNowPlayingRequest") ownedFixtureIdentity]);
        Method method = class_getClassMethod(NSRunningApplication.class, @selector(runningApplicationsWithBundleIdentifier:));
        IMP original = method_setImplementation(method, (IMP)ownedRunningApplications);
        NSData *a = png(2, 255, 0), *b = png(2, 0, 255);
        check(![a isEqualToData:b]);
        NSString *mode = @(argv[1]);
        if ([mode isEqualToString:@"identity"]) identities(a);
        else if ([mode isEqualToString:@"during-read"]) whileReading(a);
        else if ([mode isEqualToString:@"artwork"]) noArtworkIdentifier(a, b);
        else if ([mode isEqualToString:@"bounds"]) bounds(a);
        else abort();
        method_setImplementation(method, original);
        NSData *result = [NSJSONSerialization dataWithJSONObject:@{ @"result": @"PASS", @"checks": @(checks),
            @"mode": mode, @"nativeMediaQueries": @0, @"originalMethodRestored": @YES } options:0 error:nil];
        fwrite(result.bytes, 1, result.length, stdout);
    }
    return 0;
}
'''


class SceneMediaObserverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("macOS SDK is unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-media-observer-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
        archlib = subprocess.check_output(["/usr/bin/perl", "-MConfig", "-e", "print $Config{archlib}"], text=True)
        headers = Path(sdk) / archlib.lstrip("/") / "CORE"
        if not (headers / "XSUB.h").is_file():
            raise unittest.SkipTest("public Perl XS SDK headers are unavailable")
        cls.source_identity = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
        harness = root / "harness.m"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "observer-cpu"
        compiled = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-Wno-compound-token-split-by-macro",
            "-isystem", str(headers), "-I", str(SOURCE.parent), str(harness),
            "-framework", "Foundation", "-framework", "AppKit", "-framework", "ImageIO",
            "-L", str(headers), "-lperl", "-undefined", "dynamic_lookup", "-o", str(cls.binary)],
            capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != cls.source_identity:
            raise RuntimeError("observer input changed while compiling")

    def run_mode(self, mode, minimum_checks):
        executed = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=15)
        self.assertEqual(executed.returncode, 0, executed.stderr)
        result = json.loads(executed.stdout)
        self.assertEqual(result["result"], "PASS")
        self.assertGreaterEqual(result["checks"], minimum_checks)
        self.assertEqual(result["nativeMediaQueries"], 0)
        self.assertTrue(result["originalMethodRestored"])
        self.assertEqual(hashlib.sha256(SOURCE.read_bytes()).hexdigest(), self.source_identity)

    def test_full_path_and_content_identity_guards(self):
        self.run_mode("identity", 18)

    def test_artwork_read_rejects_path_or_content_change(self):
        self.run_mode("during-read", 16)

    def test_missing_artwork_identifier_compares_bytes_and_clears(self):
        self.run_mode("artwork", 16)

    def test_optional_metadata_artwork_types_and_budgets_fail_locally(self):
        self.run_mode("bounds", 32)


class SceneMediaObserverBuildTests(unittest.TestCase):
    def test_release_removes_only_experimental_helper_before_compiler_inputs(self):
        with tempfile.TemporaryDirectory(prefix="mwx-media-release-") as temporary:
            destination = Path(temporary)
            helper = destination / "SceneMediaObserver.dylib"
            keep = destination / "keep.txt"
            helper.write_bytes(b"owned stale helper")
            keep.write_bytes(b"owned neighbour must survive")
            executed = subprocess.run([
                "/bin/bash", str(ROOT / "script/build-scene-media-observer.sh"), str(destination),
            ], env={"CONFIGURATION": "Release", "PATH": "/usr/bin:/bin"},
                capture_output=True, text=True, timeout=10)
            self.assertEqual(executed.returncode, 0, executed.stderr)
            self.assertFalse(helper.exists())
            self.assertEqual(keep.read_bytes(), b"owned neighbour must survive")
            self.assertEqual(set(destination.iterdir()), {keep})


if __name__ == "__main__":
    unittest.main()
