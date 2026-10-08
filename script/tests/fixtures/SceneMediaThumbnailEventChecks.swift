import Foundation

// Inbox events have independent generations and must retain unrelated committed
// fields when an image, color, property, timeline, or playback update is rejected.
func checkMediaThumbnailEvents(
    firstImage a: Data,
    nextImage b: Data
) -> [String: Any] {
    let eventInbox = SceneMediaThumbnailInbox()
    let primaryColor = SIMD3(0.125, 0.5, 1.0)
    let secondaryColor = SIMD3(0.75, 0.25, 0.5)
    let tertiaryColor = SIMD3(0.2, 0.4, 0.6)
    let textColor = SIMD3(0.9, 0.8, 0.7)
    let highContrastColor = SIMD3(1.0, 1.0, 1.0)
    let replacementColor = SIMD3(0.05, 0.15, 0.25)
    let eventInitial = eventInbox.latest()
    let propertiesAccepted = eventInbox.publishMediaProperties(
        title: "Fixture Song", artist: "Fixture Artist", subTitle: "Fixture Live",
        albumTitle: "Fixture Album", albumArtist: "Fixture Album Artist", genres: "Rock,Pop", contentType: "music"
    )
    let afterProperties = eventInbox.latest()
    let duplicatePropertiesAccepted = eventInbox.publishMediaProperties(
        title: "Fixture Song", artist: "Fixture Artist", subTitle: "Fixture Live",
        albumTitle: "Fixture Album", albumArtist: "Fixture Album Artist", genres: "Rock,Pop", contentType: "music"
    )
    let afterDuplicateProperties = eventInbox.latest()
    let titleChangeAccepted = eventInbox.publishMediaProperties(
        title: "Replacement Song",
        artist: "Fixture Artist"
    )
    let afterTitleChange = eventInbox.latest()
    let artistChangeAccepted = eventInbox.publishMediaProperties(
        title: "Replacement Song",
        artist: "Replacement Artist"
    )
    let afterArtistChange = eventInbox.latest()
    let controlPropertyRejected = !eventInbox.publishMediaProperties(
        title: "Replacement Song", artist: "Replacement Artist",
        albumArtist: "Line\nBreak"
    )
    let oversizedPropertyRejected = !eventInbox.publishMediaProperties(
        title: "Replacement Song", artist: "Replacement Artist",
        subTitle: String(repeating: "界", count: 1_366)
    )
    let afterInvalidProperties = eventInbox.latest()
    let timelineAccepted = eventInbox.publishMediaTimeline(
        position: 12.5, duration: 90
    )
    let afterTimeline = eventInbox.latest()
    let duplicateTimelineAccepted = eventInbox.publishMediaTimeline(
        position: 12.5, duration: 90
    )
    let afterDuplicateTimeline = eventInbox.latest()
    let seekTimelineAccepted = eventInbox.publishMediaTimeline(
        position: 3.25, duration: 90
    )
    let afterTimelineSeek = eventInbox.latest()
    let negativeTimelineRejected = !eventInbox.publishMediaTimeline(
        position: -1, duration: 90
    )
    let nonFiniteTimelineRejected = !eventInbox.publishMediaTimeline(
        position: 3.25, duration: .infinity
    )
    let afterInvalidTimeline = eventInbox.latest()
    let imageColorAccepted = eventInbox.publish(
        a,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: tertiaryColor,
        textColor: textColor,
        highContrastColor: highContrastColor
    )
    let afterImageColor = eventInbox.latest()
    let duplicateImageColorAccepted = eventInbox.publish(
        a,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: tertiaryColor,
        textColor: textColor,
        highContrastColor: highContrastColor
    )
    let afterDuplicateImageColor = eventInbox.latest()
    let replacementColorAccepted = eventInbox.publish(
        a,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: replacementColor,
        textColor: textColor,
        highContrastColor: highContrastColor
    )
    let afterReplacementColor = eventInbox.latest()
    let nanColorRejected = !eventInbox.publish(
        b,
        primaryColor: SIMD3(.nan, 0.25, 0.5)
    )
    let negativeColorRejected = !eventInbox.publish(
        b,
        textColor: SIMD3(-0.01, 0.25, 0.5)
    )
    let oversizedColorRejected = !eventInbox.publish(
        b,
        highContrastColor: SIMD3(0.75, 1.01, 0.5)
    )
    let emptyImageWithColorRejected = !eventInbox.publish(
        Data(),
        tertiaryColor: replacementColor
    )
    let afterInvalidColors = eventInbox.latest()
    let playbackAccepted = eventInbox.publishPlaybackState(1)
    let afterPlayback = eventInbox.latest()
    let duplicatePlaybackAccepted = eventInbox.publishPlaybackState(1)
    let afterDuplicatePlayback = eventInbox.latest()
    let pausedAccepted = eventInbox.publishPlaybackState(2)
    let afterPaused = eventInbox.latest()
    let negativePlaybackRejected = !eventInbox.publishPlaybackState(-1)
    let oversizedPlaybackRejected = !eventInbox.publishPlaybackState(3)
    let afterInvalidPlayback = eventInbox.latest()
    let nextImageAccepted = eventInbox.publish(
        b,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        tertiaryColor: tertiaryColor,
        textColor: textColor,
        highContrastColor: highContrastColor
    )
    let afterNextImage = eventInbox.latest()
    eventInbox.clear()
    let afterEventClear = eventInbox.latest()
    eventInbox.clear()
    let afterDuplicateEventClear = eventInbox.latest()
    let emptyPropertiesAccepted = eventInbox.publishMediaProperties(
        title: "",
        artist: ""
    )
    let afterEmptyProperties = eventInbox.latest()
    let duplicateEmptyPropertiesAccepted = eventInbox.publishMediaProperties(
        title: "",
        artist: ""
    )
    let afterDuplicateEmptyProperties = eventInbox.latest()

    return [
        "eventInitialEmpty": eventInitial == .empty,
        "propertiesAccepted": propertiesAccepted,
        "propertiesGeneration": afterProperties.propertiesGeneration,
        "propertiesPreserveOtherGenerations":
            afterProperties.generation == 0
            && afterProperties.playbackGeneration == 0,
        "propertiesExact": afterProperties.properties == .init(
            title: "Fixture Song", artist: "Fixture Artist", subTitle: "Fixture Live", albumTitle: "Fixture Album",
            albumArtist: "Fixture Album Artist", genres: "Rock,Pop", contentType: "music"),
        "duplicatePropertiesAccepted": duplicatePropertiesAccepted,
        "duplicatePropertiesStable": afterDuplicateProperties == afterProperties,
        "titleChangeAccepted": titleChangeAccepted,
        "titleChangeAtomic":
            afterTitleChange.propertiesGeneration == 2
            && afterTitleChange.properties == .init(title: "Replacement Song", artist: "Fixture Artist", subTitle: "", albumTitle: "",
                albumArtist: "", genres: "", contentType: ""),
        "artistChangeAccepted": artistChangeAccepted,
        "artistChangeAtomic":
            afterArtistChange.propertiesGeneration == 3
            && afterArtistChange.properties?.title == "Replacement Song"
            && afterArtistChange.properties?.artist == "Replacement Artist",
        "controlPropertyRejected": controlPropertyRejected,
        "oversizedPropertyRejected": oversizedPropertyRejected,
        "invalidPropertiesPreserveSnapshot": afterInvalidProperties == afterArtistChange,
        "timelineAccepted": timelineAccepted,
        "timelineGeneration": afterTimeline.timelineGeneration,
        "timelineExact": afterTimeline.timeline == .init(
            position: 12.5, duration: 90
        ),
        "duplicateTimelineAccepted": duplicateTimelineAccepted,
        "duplicateTimelineStable": afterDuplicateTimeline == afterTimeline,
        "seekTimelineAccepted": seekTimelineAccepted,
        "seekTimelineAllowsDecrease":
            afterTimelineSeek.timelineGeneration == 2
            && afterTimelineSeek.timeline == .init(position: 3.25, duration: 90),
        "negativeTimelineRejected": negativeTimelineRejected,
        "nonFiniteTimelineRejected": nonFiniteTimelineRejected,
        "invalidTimelinePreservesSnapshot": afterInvalidTimeline == afterTimelineSeek,
        "imageColorAccepted": imageColorAccepted,
        "imageColorGeneration": afterImageColor.generation,
        "imageColorPlaybackGeneration": afterImageColor.playbackGeneration,
        "imageColorPreservesProperties":
            afterImageColor.properties == afterArtistChange.properties
            && afterImageColor.propertiesGeneration
                == afterArtistChange.propertiesGeneration,
        "imageColorPreservesTimeline":
            afterImageColor.timeline == afterTimelineSeek.timeline
            && afterImageColor.timelineGeneration == afterTimelineSeek.timelineGeneration,
        "imageColorExact":
            afterImageColor.primaryColor == primaryColor
            && afterImageColor.secondaryColor == secondaryColor
            && afterImageColor.tertiaryColor == tertiaryColor
            && afterImageColor.textColor == textColor
            && afterImageColor.highContrastColor == highContrastColor,
        "duplicateImageColorAccepted": duplicateImageColorAccepted,
        "duplicateImageColorGenerationStable":
            afterDuplicateImageColor.generation == afterImageColor.generation,
        "replacementColorAccepted": replacementColorAccepted,
        "replacementColorGeneration": afterReplacementColor.generation,
        "replacementColorExact":
            afterReplacementColor.primaryColor == primaryColor
            && afterReplacementColor.secondaryColor == secondaryColor
            && afterReplacementColor.tertiaryColor == replacementColor
            && afterReplacementColor.textColor == textColor
            && afterReplacementColor.highContrastColor == highContrastColor,
        "nanColorRejected": nanColorRejected,
        "negativeColorRejected": negativeColorRejected,
        "oversizedColorRejected": oversizedColorRejected,
        "emptyImageWithColorRejected": emptyImageWithColorRejected,
        "invalidColorsPreserveSnapshot": afterInvalidColors == afterReplacementColor,
        "playbackAccepted": playbackAccepted,
        "playbackState": afterPlayback.playbackState ?? -1,
        "playbackGeneration": afterPlayback.playbackGeneration,
        "playbackPreservesImageGeneration":
            afterPlayback.generation == afterReplacementColor.generation,
        "duplicatePlaybackAccepted": duplicatePlaybackAccepted,
        "duplicatePlaybackGenerationStable":
            afterDuplicatePlayback.playbackGeneration == afterPlayback.playbackGeneration,
        "pausedAccepted": pausedAccepted,
        "pausedState": afterPaused.playbackState ?? -1,
        "pausedGeneration": afterPaused.playbackGeneration,
        "negativePlaybackRejected": negativePlaybackRejected,
        "oversizedPlaybackRejected": oversizedPlaybackRejected,
        "invalidPlaybackPreservesSnapshot": afterInvalidPlayback == afterPaused,
        "nextImageAccepted": nextImageAccepted,
        "nextImageGeneration": afterNextImage.generation,
        "nextImagePreservesPlaybackGeneration":
            afterNextImage.playbackGeneration == afterPaused.playbackGeneration,
        "eventClearGeneration": afterEventClear.generation,
        "eventClearColorIsZero":
            afterEventClear.primaryColor == .zero
            && afterEventClear.secondaryColor == .zero
            && afterEventClear.tertiaryColor == .zero
            && afterEventClear.textColor == .zero
            && afterEventClear.highContrastColor == .zero,
        "eventClearPreservesPlayback":
            afterEventClear.playbackState == afterPaused.playbackState
            && afterEventClear.playbackGeneration == afterPaused.playbackGeneration,
        "eventClearPreservesProperties":
            afterEventClear.properties == afterArtistChange.properties
            && afterEventClear.propertiesGeneration
                == afterArtistChange.propertiesGeneration,
        "eventClearPreservesTimeline":
            afterEventClear.timeline == afterTimelineSeek.timeline
            && afterEventClear.timelineGeneration == afterTimelineSeek.timelineGeneration,
        "duplicateEventClearStable": afterDuplicateEventClear == afterEventClear,
        "emptyPropertiesAccepted": emptyPropertiesAccepted,
        "emptyPropertiesClearOldValues":
            afterEmptyProperties.properties?.title == ""
            && afterEmptyProperties.properties?.artist == "",
        "emptyPropertiesGeneration": afterEmptyProperties.propertiesGeneration,
        "emptyPropertiesPreserveOtherGenerations":
            afterEmptyProperties.generation == afterEventClear.generation
            && afterEmptyProperties.playbackGeneration
                == afterEventClear.playbackGeneration,
        "duplicateEmptyPropertiesAccepted": duplicateEmptyPropertiesAccepted,
        "duplicateEmptyPropertiesStable":
            afterDuplicateEmptyProperties == afterEmptyProperties,
    ]
}
