//
//  APNGDecodingOptions.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//

import Foundation

public extension APNGImage {
    /// Decoding options you can use when creating an APNG image view.
    struct DecodingOptions: OptionSet, Sendable { // 添加 Sendable 协议
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
            rawValue: 1 << 4 |
                fullFirstPass.rawValue |
                cacheDecodedImages.rawValue
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

    // 并发安全的 actor 用于缓存策略（如后续需要可扩展）
    internal actor CachePolicyStore {
        private var policy: CachePolicy = .noCache
        func set(_ policy: CachePolicy) { self.policy = policy }
        func get() -> CachePolicy { policy }
    }

    enum CachePolicy {
        /// Does not cache the decoded frame images.
        case noCache
        /// Caches the decoded frame images.
        case cache
    }
}
