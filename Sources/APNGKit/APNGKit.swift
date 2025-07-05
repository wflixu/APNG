// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import SwiftUI
import CoreGraphics

// 测试 组件是否可以被引用，先写一个简单的 View，显示 resources 中的png 图片
public struct PNGImageView: View {
    @State var imageUrl: URL?

    public init() {}

    public var body: some View {
        VStack {
            Text("load png image").font(.title)
            Image("sample", bundle: .module)
                               .renderingMode(.original)
        }.onAppear {
            loadImage();
        }
    }

    // loadImage
    public func loadImage() {
        guard let lsimageURL = Bundle.module.url(
            forResource: "sample",
            withExtension: "png",
            subdirectory: "Images"
        ) else {
            print("Image not found")
            return
        }
        print(lsimageURL.path);
    }
}



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

// 兼容类型定义
public typealias PlatformDrivingTimer = NormalTimer
public typealias PlatformView = AnyView
public typealias PlatformImage = Image

var screenScale: CGFloat {
    #if os(iOS) || os(tvOS) || os(watchOS)
    UIScreen.main.scale
    #elseif os(macOS)
    NSScreen.main?.backingScaleFactor ?? 1.0
    #else
    1.0
    #endif
}

extension Notification.Name {
    static let applicationDidBecomeActive = Notification.Name("applicationDidBecomeActive")
}

