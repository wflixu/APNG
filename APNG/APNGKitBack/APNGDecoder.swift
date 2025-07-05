//
//  APNGDecoder.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//

import Foundation
import Accelerate
import ImageIO
import zlib

// 并发安全的 actor 用于存储和管理帧及缓存
actor FrameStore {
    nonisolated(unsafe) static func makeSendable<T>(_ value: T) -> T { value }

    private var frames: [APNGFrame?]
    private var decodedImageCache: [CGImage?]?
    let cachePolicy: APNGImage.CachePolicy
    let animationControl: acTL

    init(frameCount: Int, cachePolicy: APNGImage.CachePolicy, animationControl: acTL) {
        self.frames = [APNGFrame?](repeating: nil, count: frameCount)
        self.cachePolicy = cachePolicy
        self.animationControl = animationControl
        if cachePolicy == .cache {
            self.decodedImageCache = [CGImage?](repeating: nil, count: frameCount)
        }
    }

    func framesCount() -> Int { frames.count }

    func frame(at index: Int) -> APNGFrameSendable? {
        guard let frame = frames[index] else { return nil }
        return APNGFrameSendable(frame)
    }

    func set(frame: APNGFrame, at index: Int) { frames[index] = frame }
    func loadedFrames() -> [APNGFrameSendable] { frames.compactMap { $0.map { APNGFrameSendable($0) } } }
    func isFirstFrameLoaded() -> Bool { frames[0] != nil }
    func isDuringFirstPass() -> Bool { frames.contains { $0 == nil } }

    func cachedImage(at index: Int) -> CGImage? {
        guard cachePolicy == .cache else { return nil }
        return decodedImageCache?[index]
    }
    func setCachedImage(_ image: CGImage, at index: Int) {
        guard cachePolicy == .cache else { return }
        decodedImageCache?[index] = image
    }
    func resetDecodedImageCache() {
        guard cachePolicy == .cache else { return }
        decodedImageCache = [CGImage?](repeating: nil, count: animationControl.numberOfFrames)
    }
    func isAllFramesCached() -> Bool {
        guard let cache = decodedImageCache else { return false }
        return cache.allSatisfy { $0 != nil }
    }
}

// 用于跨actor传递的Sendable包装
struct APNGFrameSendable: @unchecked Sendable {
    let frame: APNGFrame
    init(_ frame: APNGFrame) { self.frame = frame }
}

// Decodes an APNG to necessary information.
class APNGDecoder {
    struct FirstFrameResult {
        let frame: APNGFrame
        let frameImageData: Data
        let defaultImageChunks: [IDAT]
        let dataBeforeFirstFrame: Data
    }

    struct ResetStatus {
        let offset: UInt64
        let expectedSequenceNumber: Int
    }

    let reader: Reader
    let options: APNGImage.DecodingOptions
    let cachePolicy: APNGImage.CachePolicy

    // Called when the first pass is done.
    var onFirstPassDone: (() -> Void)?

    let imageHeader: IHDR
    let animationControl: acTL

    // actor 替换原有的并发队列和数组
    private let frameStore: FrameStore

    var defaultImageChunks: [IDAT] { firstFrameResult?.defaultImageChunks ?? [] }
    private(set) var firstFrameResult: FirstFrameResult?

    var canvasFullRect: CGRect { .init(origin: .zero, size: canvasFullSize) }
    private var canvasFullSize: CGSize { .init(width: imageHeader.width, height: imageHeader.height) }

    private(set) var sharedData = Data()
    private(set) var resetStatus: ResetStatus!

    convenience init(data: Data, options: APNGImage.DecodingOptions = []) async throws {
        let reader = DataReader(data: data)
        try await self.init(reader: reader, options: options)
    }

    convenience init(fileURL: URL, options: APNGImage.DecodingOptions = []) async throws {
        let reader = try FileReader(url: fileURL)
        try await self.init(reader: reader, options: options)
    }

    private init(reader: Reader, options: APNGImage.DecodingOptions) async throws {
        self.reader = reader
        self.options = options

        let skipChecksumVerify = options.contains(.skipChecksumVerify)

        guard let signature = try reader.read(upToCount: 8),
              signature.bytes == Self.pngSignature
        else {
            throw APNGKitError.decoderError(.fileFormatError)
        }
        let ihdr = try reader.readChunk(type: IHDR.self, skipChecksumVerify: skipChecksumVerify)
        imageHeader = ihdr.chunk

        let acTLResult: UntilChunkResult<acTL>
        do {
            acTLResult = try reader.readUntil(type: acTL.self, skipChecksumVerify: skipChecksumVerify)
        } catch {
            throw APNGKitError.decoderError(.lackOfChunk(acTL.name))
        }

        let numberOfFrames = acTLResult.chunk.numberOfFrames
        if numberOfFrames == 0 {
            throw APNGKitError.decoderError(.invalidNumberOfFrames(value: 0))
        }
        if numberOfFrames >= 1024 && !options.contains(.unlimitedFrameCount) {
            printLog("The input frame count exceeds the upper limit. Consider to make sure the frame count is correct " +
                     "or set `.unlimitedFrameCount` to allow huge frame count at your risk.")
            throw APNGKitError.decoderError(.invalidNumberOfFrames(value: numberOfFrames))
        }

        // cachePolicy 逻辑保持不变
        if options.contains(.cacheDecodedImages) {
            cachePolicy = .cache
        } else if options.contains(.notCacheDecodedImages) {
            cachePolicy = .noCache
        } else {
            if acTLResult.chunk.numberOfPlays == 0 {
                let estimatedTotalBytes = imageHeader.height * imageHeader.bytesPerRow * numberOfFrames
                cachePolicy = await estimatedTotalBytes < APNGImage.maximumCacheSize() ? .cache : .noCache
            } else {
                cachePolicy = .noCache
            }
        }

        sharedData.append(acTLResult.dataBeforeThunk)
        animationControl = acTLResult.chunk
        frameStore = FrameStore(frameCount: acTLResult.chunk.numberOfFrames, cachePolicy: cachePolicy, animationControl: animationControl)
    }

    // MARK: - 并发安全的帧操作 async 接口

    var framesCount: Int {
        get async { await frameStore.framesCount() }
    }

    func frame(at index: Int) async -> APNGFrame? {
        // 跨actor返回Sendable包装，再解包
        await frameStore.frame(at: index)?.frame
    }

    func set(frame: APNGFrame, at index: Int) async {
        await frameStore.set(frame: frame, at: index)
    }

    func cachedImage(at index: Int) async -> CGImage? {
        await frameStore.cachedImage(at: index)
    }

    func setCachedImage(_ image: CGImage, at index: Int) async {
        await frameStore.setCachedImage(image, at: index)
    }

    func resetDecodedImageCache() async {
        await frameStore.resetDecodedImageCache()
    }

    var loadedFrames: [APNGFrame] {
        get async { (await frameStore.loadedFrames()).map { $0.frame } }
    }

    var isFirstFrameLoaded: Bool {
        get async { await frameStore.isFirstFrameLoaded() }
    }

    var isAllFramesCached: Bool {
        get async { await frameStore.isAllFramesCached() }
    }

    var isDuringFirstPass: Bool {
        get async { await frameStore.isDuringFirstPass() }
    }

    // 兼容旧接口，首次解码完成时调用回调
    func setFirstFrameLoaded(frameResult: FirstFrameResult) async {
        guard firstFrameResult == nil else { return }
        firstFrameResult = frameResult
        sharedData.append(contentsOf: frameResult.dataBeforeFirstFrame)
        await set(frame: frameResult.frame, at: 0)
        onFirstPassDone?()
    }

    func setResetStatus(offset: UInt64, expectedSequenceNumber: Int) {
        guard resetStatus == nil else { return }
        resetStatus = ResetStatus(offset: offset, expectedSequenceNumber: expectedSequenceNumber)
    }
}

extension APNGDecoder {
    static let pngSignature: [Byte] = [
        0x89, 0x50, 0x4E, 0x47,
        0x0D, 0x0A, 0x1A, 0x0A
    ]
    static let IENDBytes: [Byte] = [
        0x00, 0x00, 0x00, 0x00,
        0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82
    ]
    func generateImageData(frameControl: fcTL, data: Data) throws -> Data {
        try generateImageData(width: frameControl.width, height: frameControl.height, data: data)
    }
    private func generateImageData(width: Int, height: Int, data: Data) throws -> Data {
        let ihdr = try imageHeader.updated(width: width, height: height).encode()
        let idat = IDAT.encode(data: data)
        return Self.pngSignature + ihdr + sharedData + idat + Self.IENDBytes
    }
}

extension APNGDecoder {
    func createDefaultImageData() throws -> Data {
        let payload = try defaultImageChunks.map { idat in
            try idat.loadData(with: self.reader)
        }.joined()
        let data = try generateImageData(width: imageHeader.width, height: imageHeader.height, data: Data(payload))
        return data
    }
}

/// A frame data of an APNG image. It contains a frame control chunk.
public struct APNGFrame {
    
    /// The frame control chunk of this frame.
    public let frameControl: fcTL
    
    let data: [DataChunk]
    
    func loadData(with reader: Reader) throws -> Data {
        Data(
            try data.map { try $0.loadData(with: reader) }
                    .joined()
        )
    }
    
    func normalizedRect(fullHeight: Int) -> CGRect {
        frameControl.normalizedRect(fullHeight: fullHeight)
    }
}

extension fcTL {
    func normalizedRect(fullHeight: Int) -> CGRect {
        .init(x: xOffset, y: fullHeight - yOffset - height, width: width, height: height)
    }

    var cgRect: CGRect {
        .init(x: xOffset, y: yOffset, width: width, height: height)
    }
}
