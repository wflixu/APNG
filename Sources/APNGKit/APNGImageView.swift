
// 仅支持 SwiftUI，macOS 15+，Swift 6 并发安全环境
import Foundation
import SwiftUI
import CoreGraphics

/// SwiftUI 下用于显示和播放 APNGImage 的 View
public struct APNGImageView: View {
    public typealias PlayedLoopCount = Int
    public typealias FrameIndex = Int

    @State private var currentFrame: CGImage?
    @State private var displayingFrameIndex: Int = 0
    @State private var playedCount: Int = 0
    @State private var timer: Timer?
    @State private var isAnimating: Bool = false

    private let image: APNGImage?
    private let staticImage: PlatformImage?
    private let autoStartAnimationWhenSetImage: Bool

    // 回调闭包
    public var onOnePlayDone: ((PlayedLoopCount) -> Void)?
    public var onAllPlaysDone: (() -> Void)?
    public var onFrameMissed: ((FrameIndex) -> Void)?
    public var onFallBackToDefaultImage: (() -> Void)?
    public var onFallBackToDefaultImageFailed: ((APNGKitError) -> Void)?
    public var onDecodingFrameError: ((DecodingErrorItem) -> Void)?

    public init(
        image: APNGImage?,
        staticImage: PlatformImage? = nil,
        autoStartAnimationWhenSetImage: Bool = true,
        onOnePlayDone: ((PlayedLoopCount) -> Void)? = nil,
        onAllPlaysDone: (() -> Void)? = nil,
        onFrameMissed: ((FrameIndex) -> Void)? = nil,
        onFallBackToDefaultImage: (() -> Void)? = nil,
        onFallBackToDefaultImageFailed: ((APNGKitError) -> Void)? = nil,
        onDecodingFrameError: ((DecodingErrorItem) -> Void)? = nil
    ) {
        self.image = image
        self.staticImage = staticImage
        self.autoStartAnimationWhenSetImage = autoStartAnimationWhenSetImage
        self.onOnePlayDone = onOnePlayDone
        self.onAllPlaysDone = onAllPlaysDone
        self.onFrameMissed = onFrameMissed
        self.onFallBackToDefaultImage = onFallBackToDefaultImage
        self.onFallBackToDefaultImageFailed = onFallBackToDefaultImageFailed
        self.onDecodingFrameError = onDecodingFrameError
    }

    public var body: some View {
        Group {
            if let cgImage = currentFrame {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let staticImage = staticImage {
                staticImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if autoStartAnimationWhenSetImage {
                startAnimating()
            } else {
                showFirstFrame()
            }
        }
        .onDisappear {
            stopAnimating()
        }
    }

    private func showFirstFrame() {
        guard let image = image else { return }
        if let frame = image.decoder.frame(at: 0)?.image {
            currentFrame = frame
            displayingFrameIndex = 0
        }
    }

    private func startAnimating() {
        guard let image = image, image.decoder.framesCount > 1 else {
            showFirstFrame()
            return
        }
        isAnimating = true
        playedCount = 0
        displayingFrameIndex = 0
        updateFrame()
        timer = Timer.scheduledTimer(withTimeInterval: image.decoder.frame(at: 0)?.frameControl.duration ?? 0.1, repeats: true) { _ in
            step()
        }
    }

    private func stopAnimating() {
        isAnimating = false
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        guard let image = image else { return }
        let framesCount = image.decoder.framesCount
        let nextIndex = (displayingFrameIndex + 1) % framesCount
        if let frame = image.decoder.frame(at: nextIndex)?.image {
            currentFrame = frame
            displayingFrameIndex = nextIndex
            if nextIndex == 0 {
                playedCount += 1
                onOnePlayDone?(playedCount)
                if !image.playForever, let numberOfPlays = image.numberOfPlays, playedCount >= numberOfPlays {
                    stopAnimating()
                    onAllPlaysDone?()
                }
            }
        } else {
            onFrameMissed?(nextIndex)
        }
    }

    private func updateFrame() {
        guard let image = image else { return }
        if let frame = image.decoder.frame(at: displayingFrameIndex)?.image {
            currentFrame = frame
        }
    }

    public struct DecodingErrorItem {
        public let error: APNGKitError
        public let canFallbackToDefaultImage: Bool
    }
}



public typealias PlatformDrivingTimer = NormalTimer
public typealias PlatformImage = Image

var screenScale: CGFloat {
    // SwiftUI 下通常为 1.0，或可通过 NSScreen.main?.backingScaleFactor 获取
    NSScreen.main?.backingScaleFactor ?? 1.0
}

extension Notification.Name {
    static var applicationDidBecomeActive: Notification.Name {
        Notification.Name("NSApplicationDidBecomeActiveNotification")
    }
}
