import Foundation
import os.lock

/// Producer-agnostic media ingress. Artwork and its event-derived color share
/// one generation; playback and title/artist properties each advance their own
/// generation because either can change without replacing artwork.
final class SceneMediaThumbnailInbox: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        struct Properties: Equatable, Sendable {
            let title: String
            let artist: String
        }

        let current: Data?
        let primaryColor: SIMD3<Double>?
        let secondaryColor: SIMD3<Double>?
        let tertiaryColor: SIMD3<Double>?
        let textColor: SIMD3<Double>?
        let highContrastColor: SIMD3<Double>?
        let generation: UInt64
        let playbackState: Int?
        let playbackGeneration: UInt64
        let properties: Properties?
        let propertiesGeneration: UInt64

        init(
            current: Data?,
            primaryColor: SIMD3<Double>? = nil,
            secondaryColor: SIMD3<Double>?,
            tertiaryColor: SIMD3<Double>? = nil,
            textColor: SIMD3<Double>? = nil,
            highContrastColor: SIMD3<Double>? = nil,
            generation: UInt64,
            playbackState: Int?,
            playbackGeneration: UInt64,
            properties: Properties? = nil,
            propertiesGeneration: UInt64 = 0
        ) {
            self.current = current
            self.primaryColor = primaryColor
            self.secondaryColor = secondaryColor
            self.tertiaryColor = tertiaryColor
            self.textColor = textColor
            self.highContrastColor = highContrastColor
            self.generation = generation
            self.playbackState = playbackState
            self.playbackGeneration = playbackGeneration
            self.properties = properties
            self.propertiesGeneration = propertiesGeneration
        }

        static let empty = Snapshot(
            current: nil,
            primaryColor: nil,
            secondaryColor: nil,
            generation: 0,
            playbackState: nil,
            playbackGeneration: 0
        )
    }

    static let shared = SceneMediaThumbnailInbox()
    nonisolated static let maximumEncodedByteCount = 16 * 1_024 * 1_024
    nonisolated static let maximumMediaPropertyUTF8ByteCount = 4 * 1_024

    private var lock = os_unfair_lock_s()
    private var snapshot = Snapshot.empty

    init() {}

    func latest() -> Snapshot {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return snapshot
    }

    @discardableResult
    func publish(
        _ encodedImage: Data,
        primaryColor: SIMD3<Double>? = nil,
        secondaryColor: SIMD3<Double>? = nil,
        tertiaryColor: SIMD3<Double>? = nil,
        textColor: SIMD3<Double>? = nil,
        highContrastColor: SIMD3<Double>? = nil
    ) -> Bool {
        guard !encodedImage.isEmpty,
              encodedImage.count <= Self.maximumEncodedByteCount,
              primaryColor.map(Self.isNormalizedColor) != false,
              secondaryColor.map(Self.isNormalizedColor) != false,
              tertiaryColor.map(Self.isNormalizedColor) != false,
              textColor.map(Self.isNormalizedColor) != false,
              highContrastColor.map(Self.isNormalizedColor) != false else {
            return false
        }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != encodedImage
                || snapshot.primaryColor != primaryColor
                || snapshot.secondaryColor != secondaryColor
                || snapshot.tertiaryColor != tertiaryColor
                || snapshot.textColor != textColor
                || snapshot.highContrastColor != highContrastColor else {
            return true
        }
        guard snapshot.generation < .max else { return false }
        snapshot = Snapshot(
            current: encodedImage,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            tertiaryColor: tertiaryColor,
            textColor: textColor,
            highContrastColor: highContrastColor,
            generation: snapshot.generation + 1,
            playbackState: snapshot.playbackState,
            playbackGeneration: snapshot.playbackGeneration,
            properties: snapshot.properties,
            propertiesGeneration: snapshot.propertiesGeneration
        )
        return true
    }

    @discardableResult
    func publishPlaybackState(_ state: Int) -> Bool {
        guard (0...2).contains(state) else { return false }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.playbackState != state else { return true }
        guard snapshot.playbackGeneration < .max else { return false }
        snapshot = Snapshot(
            current: snapshot.current,
            primaryColor: snapshot.primaryColor,
            secondaryColor: snapshot.secondaryColor,
            tertiaryColor: snapshot.tertiaryColor,
            textColor: snapshot.textColor,
            highContrastColor: snapshot.highContrastColor,
            generation: snapshot.generation,
            playbackState: state,
            playbackGeneration: snapshot.playbackGeneration + 1,
            properties: snapshot.properties,
            propertiesGeneration: snapshot.propertiesGeneration
        )
        return true
    }

    @discardableResult
    func publishMediaProperties(title: String, artist: String) -> Bool {
        guard Self.isValidMediaProperty(title),
              Self.isValidMediaProperty(artist) else {
            return false
        }
        let properties = Snapshot.Properties(title: title, artist: artist)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.properties != properties else { return true }
        guard snapshot.propertiesGeneration < .max else { return false }
        snapshot = Snapshot(
            current: snapshot.current,
            primaryColor: snapshot.primaryColor,
            secondaryColor: snapshot.secondaryColor,
            tertiaryColor: snapshot.tertiaryColor,
            textColor: snapshot.textColor,
            highContrastColor: snapshot.highContrastColor,
            generation: snapshot.generation,
            playbackState: snapshot.playbackState,
            playbackGeneration: snapshot.playbackGeneration,
            properties: properties,
            propertiesGeneration: snapshot.propertiesGeneration + 1
        )
        return true
    }

    func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard snapshot.current != nil, snapshot.generation < .max else { return }
        snapshot = Snapshot(
            current: nil,
            primaryColor: .zero,
            secondaryColor: .zero,
            tertiaryColor: .zero,
            textColor: .zero,
            highContrastColor: .zero,
            generation: snapshot.generation + 1,
            playbackState: snapshot.playbackState,
            playbackGeneration: snapshot.playbackGeneration,
            properties: snapshot.properties,
            propertiesGeneration: snapshot.propertiesGeneration
        )
    }

    nonisolated private static func isNormalizedColor(
        _ value: SIMD3<Double>
    ) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
            && (0...1).contains(value.x)
            && (0...1).contains(value.y)
            && (0...1).contains(value.z)
    }

    nonisolated private static func isValidMediaProperty(
        _ value: String
    ) -> Bool {
        guard let data = value.data(using: .utf8),
              data.count <= maximumMediaPropertyUTF8ByteCount else {
            return false
        }
        return !value.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        })
    }
}
