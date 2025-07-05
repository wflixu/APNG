//  APNGImage.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//

import CoreGraphics
import Foundation

/// APNG 图片对象，支持 SwiftUI，macOS 15，Swift 6.1，并发安全
public actor APNGImage {
    // MARK: - 静态缓存配置

    private static var _maximumCacheSize: Int = 50_000_000 // 50 MB

    public static func maximumCacheSize() -> Int {
        _maximumCacheSize
    }

    public static func setMaximumCacheSize(_ newValue: Int) {
        _maximumCacheSize = newValue
    }

    public static let MIMEType: String = "image/apng"

    public enum Duration {
        case loadedPartial(TimeInterval)
        case full(TimeInterval)
    }

    // MARK: - 实例属性

    let decoder: APNGDecoder
    public let scale: CGFloat
    public var numberOfPlays: Int?
    var playForever: Bool { numberOfPlays == nil || numberOfPlays == 0 }

    // MARK: - 只读属性

    public var loadedFrames: [APNGFrame] {
        decoder.loadedFrames
    }

    public func cachedFrameImage(at index: Int) -> CGImage? {
        guard let cachedImages = decoder.decodedImageCache, index < cachedImages.count else {
            return nil
        }
        return cachedImages[index]
    }

    public var size: CGSize {
        .init(
            width: CGFloat(decoder.imageHeader.width) / scale,
            height: CGFloat(decoder.imageHeader.height) / scale
        )
    }

    public var numberOfFrames: Int { decoder.animationControl.numberOfFrames }
    public var duration: Duration {
        let knownDuration = decoder.loadedFrames.reduce(0.0) { $0 + ($1.frameControl.duration) }
        return decoder.isDuringFirstPass ? .loadedPartial(knownDuration) : .full(knownDuration)
    }

    public var cachePolicy: CachePolicy { decoder.cachePolicy }

    // MARK: - 初始化

    public init(
        named name: String,
        decodingOptions: DecodingOptions = []
    ) throws {
        try self.init(named: name, decodingOptions: decodingOptions, in: nil, subdirectory: nil)
    }

    public init(
        named name: String,
        decodingOptions: DecodingOptions = [],
        in bundle: Bundle?,
        subdirectory subpath: String? = nil
    ) throws {
        let guessing = FileNameGuessing(name: name)
        guard let resource = guessing.load(in: bundle, subpath: subpath) else {
            throw APNGKitError.imageError(.resourceNotFound(name: name, bundle: bundle ?? .main))
        }
        try self.init(fileURL: resource.fileURL, scale: resource.scale, decodingOptions: decodingOptions)
    }

    public init(
        filePath: String,
        scale: CGFloat? = nil,
        decodingOptions: DecodingOptions = []
    ) throws {
        let fileURL = URL(fileURLWithPath: filePath)
        try self.init(fileURL: fileURL, scale: scale, decodingOptions: decodingOptions)
    }

    public init(
        fileURL: URL,
        scale: CGFloat? = nil,
        decodingOptions: DecodingOptions = []
    ) throws {
        self.scale = scale ?? fileURL.imageScale
        do {
            decoder = try APNGDecoder(fileURL: fileURL, options: decodingOptions)
            let repeatCount = decoder.animationControl.numberOfPlays
            numberOfPlays = repeatCount == 0 ? nil : repeatCount
        } catch {
            if let apngError = error.apngError, apngError.shouldRevertToNormalImage {
                let data = try Data(contentsOf: fileURL)
                throw APNGKitError.imageError(.normalImageDataLoaded(data: data, scale: self.scale))
            } else {
                throw error
            }
        }
    }

    public init(
        data: Data,
        scale: CGFloat = 1.0,
        decodingOptions: DecodingOptions = []
    ) throws {
        self.scale = scale
        do {
            decoder = try APNGDecoder(data: data, options: decodingOptions)
            let repeatCount = decoder.animationControl.numberOfPlays
            numberOfPlays = repeatCount == 0 ? nil : repeatCount
        } catch {
            if let apngError = error.apngError, apngError.shouldRevertToNormalImage {
                throw APNGKitError.imageError(.normalImageDataLoaded(data: data, scale: self.scale))
            } else {
                throw error
            }
        }
    }
}

public extension APNGImage {
    /// Decoding options you can use when creating an APNG image view.
    struct DecodingOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Performs the first pass to decode all frames at the beginning.
        ///
        /// By default, APNGKit only decodes the minimal data from the image data or file, for example, APNG image
        /// header, animation chunk and the first frame before finishing the image initializing. Enable this to ask
        /// APNGKit to perform a full first pass before returning an image or throwing an error. This can help to
        /// detect any APNG data or file error before showing it or get the total frames information and gives you the
        /// total animation duration before actually displaying the image.
        public static let fullFirstPass = DecodingOptions(rawValue: 1 << 0)

        /// Loads and holds the actual frame data when decoding the frames in the first pass.
        ///
        /// By default, APNGKit only records the data starting index and offset for each image data chunk. Enable this
        /// to ask APNGKit to copy out the image data for each frame at the first pass. So it won't read data again in
        /// the future playing loops. This option trades a bit CPU resource with cost of taking more memory.
        public static let loadFrameData = DecodingOptions(rawValue: 1 << 1)

        /// Holds the decoded image for each frame, so APNGKit will not render it again.
        ///
        /// By default, APNGKit determines the cache policy by the image properties itself, if neither
        /// `.cacheDecodedImages` nor `.notCacheDecodedImages` is set.
        ///
        /// Enable this to forcibly ask APNGKit to create a memory cache for the decoded frames. Then when the same
        /// frame is going to be shown again, it skips the whole rendering process and just load it from cache then
        /// show. This trades for better CPU usage with the cost of memory.
        ///
        /// See ``APNGImage.CachePolicy`` for more.
        public static let cacheDecodedImages = DecodingOptions(rawValue: 1 << 2)

        /// Drops the decoded image for each frame, so APNGKit will render it again when next time it is needed.
        ///
        /// By default, APNGKit determines the cache policy by the image properties itself, if neither
        /// `.cacheDecodedImages` nor `.notCacheDecodedImages` is set.
        ///
        /// Enable this to forcibly ask APNGKit to skip the memory cache for the decoded frames. Then when the same
        /// frame is going to be shown again, it performs the rendering process and draw it again to the canvas.
        /// This trades for smaller memory footprint with the cost of CPU usage.
        ///
        /// See ``APNGImage.CachePolicy`` for more.
        public static let notCacheDecodedImages = DecodingOptions(rawValue: 1 << 3)

        /// Performs render for all frames before the APNG image finishes it initialization. This also enables
        /// `.fullFirstPass` and `.cacheDecodedImages` option.
        ///
        /// By default, APNGKit behave as just-in-time when rendering a frame. It will not render a frame until it is
        /// needed to be shown as the next frame. This requires each frame to be rendered within (1 / frameRate)
        /// seconds to keep the animation smooth without a frame dropping or frame skipped. This is the most
        /// memory-efficient way but cost more CPU resource and higher power consumption.
        ///
        /// Enable this to ask APNGKit to change the behavior to an ahead-of-time way. It performs a full load of all
        /// frames, renders them and then cache the rendered images for future use. This reduces the CPU usage
        /// dramatically when displaying the APNG image but with the most memory usage and footprint. If you have a
        /// forever-repeated image and the CPU usage or power consumption is critical, consider to enable this to
        /// perform the trade-off.
        ///
        /// If `fullFirstPass` and `cacheDecodedImages` are not set in the same decoding options, APNGKit adds them
        /// for you automatically, since only enabling `preRenderAllFrames` is meaningless.
        public static let preRenderAllFrames = DecodingOptions(
            rawValue: (1 << 4) | fullFirstPass.rawValue | cacheDecodedImages.rawValue
        )

        /// Skips verification of the checksum (CRC bytes) for each chunk in the APNG image data.
        ///
        /// By default, APNGKit verifies the checksum for all used chunks in the APNG data to make sure the image is
        /// valid and is not malformed before you use it.
        ///
        /// Enable this to ask APNGKit to skip this check. It improves the CPU performance a bit, but with the risk of
        /// reading and trust unchecked chunks. It is not recommended to skip the check.
        public static let skipChecksumVerify = DecodingOptions(rawValue: 1 << 5)

        /// Unsets frame count limitation when reading an APNG image.
        ///
        /// By default, APNGKit applies a limit for frame count of the APNG image to 1024. It should be suitable for
        /// all expected use cases. Allowing more frame count or even unlimited frames may easily causes
        ///
        public static let unlimitedFrameCount = DecodingOptions(rawValue: 1 << 6)
    }

    /// The cache policy APNGKit will use to determine whether cache the decoded frames or not.
    ///
    /// If not using cache (`.noCache` case), APNGKit renders each frame when it is going to be displayed onto screen, and drops the
    /// image as soon as the next frame is shown. It has the most efficient memory performance, but with
    /// the cost of high CPU usage, since each frame will be decoded every time it is shown.
    ///
    /// On the other hand, if using cache (`.cache` case), APNGKit caches the decoded images and prevent to draw it from
    /// data again when displaying. It consumes more memory but you can get the least CPU usage.
    enum CachePolicy: Sendable {
        /// Does not cache the decoded frame images.
        case noCache
        /// Caches the decoded frame images.
        case cache
    }
}

// 文件名推测工具
struct FileNameGuessing {
    struct Resource {
        let fileURL: URL
        let scale: CGFloat
    }

    struct GuessingResult: Equatable {
        let fileName: String
        let scale: CGFloat
    }

    let name: String
    let refScale: CGFloat?
    let fileName: String
    let guessingExtensions: [String]

    var guessingResults: [GuessingResult] {
        if fileName.hasSuffix("@2x") {
            return [GuessingResult(fileName: fileName, scale: 2)]
        } else if fileName.hasSuffix("@3x") {
            return [GuessingResult(fileName: fileName, scale: 3)]
        } else {
            let maxScale = Int(refScale ?? screenScale)
            return (1 ... maxScale).reversed().map { scale in
                if scale > 1, !fileName.hasSuffix("@\(scale)x") {
                    return GuessingResult(fileName: "\(fileName)@\(scale)x", scale: CGFloat(scale))
                } else {
                    return GuessingResult(fileName: fileName, scale: CGFloat(1))
                }
            }
        }
    }

    init(name: String, refScale: CGFloat? = nil) {
        self.name = name
        self.refScale = refScale
        let splits = name.split(separator: ".")
        if splits.count > 1 {
            guessingExtensions = [String(splits.last!)]
            fileName = splits[0 ..< splits.count - 1].joined(separator: ".")
        } else {
            guessingExtensions = ["apng", "png"]
            fileName = name
        }
    }

    func load(in bundle: Bundle?, subpath: String?) -> Resource? {
        let targetBundle = bundle ?? .main
        for guessing in guessingResults {
            for ext in guessingExtensions {
                if let url = targetBundle.url(
                    forResource: guessing.fileName, withExtension: ext, subdirectory: subpath
                ) {
                    return .init(fileURL: url, scale: guessing.scale)
                }
            }
        }
        return nil
    }
}

extension URL {
    var imageScale: CGFloat {
        var url = self
        url.deletePathExtension()
        if url.lastPathComponent.hasSuffix("@2x") {
            return 2
        } else if url.lastPathComponent.hasSuffix("@3x") {
            return 3
        } else {
            return 1
        }
    }
}
