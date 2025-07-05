
//  APNGImage.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//

import CoreGraphics
import Foundation

/// 用于线程安全管理最大缓存字节数的 actor
actor APNGImageCacheConfig {
    private var _maximumCacheSize: Int = 50_000_000 // 50 MB

    func getMaximumCacheSize() -> Int {
        _maximumCacheSize
    }

    func setMaximumCacheSize(_ newValue: Int) {
        _maximumCacheSize = newValue
    }
}

/// 全局线程安全的 APNGImage
public actor APNGImage {
    // MARK: - 静态缓存配置

    private static let cacheConfig = APNGImageCacheConfig()

    public static func maximumCacheSize() async -> Int {
        await cacheConfig.getMaximumCacheSize()
    }

    public static func setMaximumCacheSize(_ newValue: Int) async {
        await cacheConfig.setMaximumCacheSize(newValue)
    }

    public static let MIMEType: String = "image/apng"

    public enum Duration {
        case loadedPartial(TimeInterval)
        case full(TimeInterval)
    }

    // MARK: - 实例属性

    let decoder: APNGDecoder
    let encoder: APNGEncoder? = nil // 如有需要可实现

    private var _onFramesInformationPrepared: (() -> Void)?
    public var onFramesInformationPrepared: (() -> Void)? {
        get { _onFramesInformationPrepared }
        set { _onFramesInformationPrepared = newValue }
    }

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
    ) async throws {
        try await self.init(named: name, decodingOptions: decodingOptions, in: nil, subdirectory: nil)
    }

    public init(
        named name: String,
        decodingOptions: DecodingOptions = [],
        in bundle: Bundle?,
        subdirectory subpath: String? = nil
    ) async throws {
        let guessing = FileNameGuessing(name: name)
        guard let resource = guessing.load(in: bundle, subpath: subpath) else {
            throw APNGKitError.imageError(.resourceNotFound(name: name, bundle: bundle ?? .main))
        }
        try await self.init(fileURL: resource.fileURL, scale: resource.scale, decodingOptions: decodingOptions)
    }

    public init(
        filePath: String,
        scale: CGFloat? = nil,
        decodingOptions: DecodingOptions = []
    ) async throws {
        let fileURL = URL(fileURLWithPath: filePath)
        try await self.init(fileURL: fileURL, scale: scale, decodingOptions: decodingOptions)
    }

    public init(
        fileURL: URL,
        scale: CGFloat? = nil,
        decodingOptions: DecodingOptions = []
    ) async throws {
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
    ) async throws {
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
                if scale > 1, !fileName.hasSuffix("@\(scale)x") { // append scale indicator to file if there is no one.
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
