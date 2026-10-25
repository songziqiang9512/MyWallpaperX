#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (*SceneVideoSegmentCallback)(NSObject *owner,
                                     const void * _Nullable bytes,
                                     NSUInteger length,
                                     AVAssetSegmentType segmentType);

// The Swift sink owns segment validation, failure state and output.
@interface SceneVideoSegmentDelegate : NSObject <AVAssetWriterDelegate>
- (instancetype)initWithOwner:(NSObject *)owner
                     callback:(SceneVideoSegmentCallback)callback NS_SWIFT_NAME(init(owner:callback:));
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
