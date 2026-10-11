//
//  PNGValidator.swift
//  ArknightsToolBox
//
//  检查 PNG 块结构、CRC 和压缩数据，对应 resources.py 的 valid_png。
//  不使用字节数门槛，因此不会误拒正常的小图标。
//

import Foundation
import Compression

enum PNGValidator {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> Int {
        (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }

    static func isValid(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.starts(with: signature) else { return false }

        var offset = 8
        var compressed: [UInt8] = []
        var rowSizes: [Int] = []
        var sawHeader = false

        while offset + 12 <= bytes.count {
            let length = uint32(bytes, offset)
            let end = offset + 8 + length
            guard end + 4 <= bytes.count else { return false }

            let kind = Array(bytes[(offset + 4)..<(offset + 8)])
            guard crc32(bytes[(offset + 4)..<end]) == UInt32(uint32(bytes, end)) else { return false }
            if offset == 8, kind != Array("IHDR".utf8) { return false }

            if kind == Array("IHDR".utf8) {
                guard length == 13, !sawHeader else { return false }
                let width = uint32(bytes, offset + 8)
                let height = uint32(bytes, offset + 12)
                let depth = Int(bytes[offset + 16])
                let color = Int(bytes[offset + 17])
                let compression = bytes[offset + 18], filter = bytes[offset + 19]
                let interlace = Int(bytes[offset + 20])

                let channelTable = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]
                let depthTable: [Int: Set<Int>] = [0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]]
                guard let channels = channelTable[color], depthTable[color]?.contains(depth) == true,
                      compression == 0, filter == 0, interlace == 0 || interlace == 1,
                      width > 0, height > 0 else { return false }
                sawHeader = true

                let passes = interlace == 0
                    ? [(0, 0, 1, 1)]
                    : [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
                for (x, y, dx, dy) in passes {
                    let columns = max(0, (width - x + dx - 1) / dx)
                    let rows = max(0, (height - y + dy - 1) / dy)
                    if columns > 0, rows > 0 {
                        rowSizes += Array(repeating: (columns * channels * depth + 7) / 8 + 1, count: rows)
                    }
                }
            } else if kind == Array("IDAT".utf8) {
                compressed += bytes[(offset + 8)..<end]
            } else if kind == Array("IEND".utf8) {
                guard sawHeader, length == 0, !compressed.isEmpty, end + 4 == bytes.count else { return false }
                return inflatedRowsAreValid(compressed, rowSizes: rowSizes)
            }
            offset = end + 4
        }
        return false
    }

    /// 解压 IDAT 数据，核对总长度及每行的滤波类型
    private static func inflatedRowsAreValid(_ zlibData: [UInt8], rowSizes: [Int]) -> Bool {
        // zlib 流 = 2 字节头 + deflate 数据 + 4 字节 Adler-32；Compression 框架只接受裸 deflate
        guard zlibData.count > 6 else { return false }
        let deflate = Array(zlibData[2..<(zlibData.count - 4)])
        let expected = rowSizes.reduce(0, +)
        var output = [UInt8](repeating: 0, count: expected + 1)

        let written = deflate.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, destination.count,
                                          source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else { return false }

        var cursor = 0
        for size in rowSizes {
            if output[cursor] > 4 { return false }
            cursor += size
        }
        return true
    }
}
