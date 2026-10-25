#import "SceneVideoSegmentDelegate.h"

@implementation SceneVideoSegmentDelegate {
    __strong NSObject *_owner;
    SceneVideoSegmentCallback _callback;
}

- (instancetype)initWithOwner:(NSObject *)owner callback:(SceneVideoSegmentCallback)callback {
    self = [super init];
    if (self) {
        _owner = owner;
        _callback = callback;
    }
    return self;
}

// inventory-entry: AVAssetWriterDelegate invokes this synchronous borrowed-buffer adapter.
- (void)assetWriter:(AVAssetWriter *)writer
 didOutputSegmentData:(NSData *)segmentData
        segmentType:(AVAssetSegmentType)segmentType {
    (void)writer;
    __attribute__((objc_precise_lifetime)) NSObject *owner = _owner;
    __attribute__((objc_precise_lifetime)) NSData *borrowedData = segmentData;
    _callback(owner, borrowedData.bytes, borrowedData.length, segmentType);
}

@end
