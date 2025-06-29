//
//  APNGEncoder.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//
import Foundation

enum APNGEncoder {
    // CRC32 计算
    private static var crc32Table: [UInt32] = (0 ..< 256).map { i in
        (0 ..< 8).reduce(UInt32(i)) { c, _ in
            (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func pngChunk(type: String, data: Data) -> Data {
        var chunk = Data()
        var length = UInt32(data.count).bigEndian
        chunk.append(Data(bytes: &length, count: 4))
        chunk.append(type.data(using: .ascii)!)
        chunk.append(data)
        var crcInput = type.data(using: .ascii)! + data
        var crc = crc32(crcInput).bigEndian
        chunk.append(Data(bytes: &crc, count: 4))
        return chunk
    }

    /// 生成 APNG 文件
    static func generateAPNG(frames: [Data], output: URL, frameDelay: UInt16 = 10, repeatCount: UInt32 = 0) {
        guard let firstFrame = frames.first else { return }
        var apng = Data()
        // PNG Header Signature
        apng.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10])
        // 解析 IHDR 块（取自第一帧）
        let ihdrRange = 8 ..< 33
        apng.append(firstFrame[ihdrRange]) // IHDR

        // 添加 acTL 块（动画控制块）
        var acTLData = Data()
        acTLData.append(UInt32(frames.count).bigEndian.data)
        acTLData.append(repeatCount.bigEndian.data)
        apng.append(pngChunk(type: "acTL", data: acTLData))

        // 添加第一帧的 fcTL 块（帧控制块）
        apng.append(createfcTL(sequenceNumber: 0, widthHeightData: firstFrame, delay: frameDelay, isFirst: true))

        // 添加第一帧原始 IDAT 数据块（取自 PNG 第一帧）
        let idatChunks = extractChunks(from: firstFrame, type: "IDAT")
        for chunk in idatChunks {
            apng.append(chunk)
        }

        // 添加后续帧 (fcTL + fdAT)
        for (index, frame) in frames.enumerated().dropFirst() {
            apng.append(createfcTL(sequenceNumber: UInt32(index), widthHeightData: frame, delay: frameDelay, isFirst: false))
            let idatDataChunks = extractIDATData(from: frame)
            var sequenceNumber = UInt32(index)
            for idatData in idatDataChunks {
                var fdATData = Data()
                fdATData.append(sequenceNumber.bigEndian.data)
                fdATData.append(idatData)
                apng.append(pngChunk(type: "fdAT", data: fdATData))
                sequenceNumber += 1
            }
        }

        // 添加 IEND 块
        let iendRange = (firstFrame.count - 12) ..< firstFrame.count
        apng.append(firstFrame[iendRange]) // IEND

        try? apng.write(to: output)
    }

    // 提取指定类型的 chunk
    static func extractChunks(from pngData: Data, type: String) -> [Data] {
        var chunks: [Data] = []
        var cursor = 8 // Skip PNG signature
        while cursor < pngData.count {
            let length = Int(UInt32(bigEndian: pngData[cursor ..< (cursor + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }))
            let chunkType = String(bytes: pngData[(cursor + 4) ..< (cursor + 8)], encoding: .ascii)!
            let chunk = pngData[cursor ..< (cursor + 8 + length + 4)]
            if chunkType == type {
                chunks.append(chunk)
            }
            cursor += 8 + length + 4
            if chunkType == "IEND" { break }
        }
        return chunks
    }

    // 提取所有 IDAT 数据部分
    static func extractIDATData(from pngData: Data) -> [Data] {
        var dataChunks: [Data] = []
        let chunks = extractChunks(from: pngData, type: "IDAT")
        for chunk in chunks {
            let length = Int(UInt32(bigEndian: chunk.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }))
            let dataRange = 8 ..< (8 + length)
            dataChunks.append(chunk[dataRange])
        }
        return dataChunks
    }

    // 创建 fcTL 块
    static func createfcTL(sequenceNumber: UInt32, widthHeightData: Data, delay: UInt16, isFirst: Bool) -> Data {
        let ihdrRange = 16 ..< 24 // Width & Height from IHDR chunk
        let width = widthHeightData[ihdrRange.prefix(4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        let height = widthHeightData[ihdrRange.suffix(4)].withUnsafeBytes { $0.load(as: UInt32.self) }
        var data = Data()
        data.append(sequenceNumber.bigEndian.data)
        data.append(width.bigEndian.data)
        data.append(height.bigEndian.data)
        data.append(UInt32(0).bigEndian.data) // x offset
        data.append(UInt32(0).bigEndian.data) // y offset
        data.append(delay.bigEndian.data) // delay numerator
        data.append(UInt16(1000).bigEndian.data) // delay denominator
        data.append(UInt8(0)) // dispose_op (0: NONE)
        data.append(UInt8(isFirst ? 0 : 1)) // blend_op (0: SOURCE for first frame, 1: OVER for others)
        return pngChunk(type: "fcTL", data: data)
    }
}

// 辅助扩展
extension FixedWidthInteger {
    var data: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
