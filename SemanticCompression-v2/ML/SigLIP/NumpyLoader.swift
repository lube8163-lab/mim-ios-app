import Foundation

// 読み込んだ .npy を保持するための簡単な構造体
struct NumpyArrayF {
    let shape: [Int]   // 例: [634, 768]
    let data: [Float]  // shape の要素数を全部掛けた長さ
}

enum NumpyLoaderError: Error {
    case invalidFormat
    case unsupportedDtype
    case unsupportedVersion
    case invalidHeader
    case sizeMismatch
}

struct NumpyLoader {

    /// .npy (float32, C-order) を読み込む
    static func loadNpy(from url: URL) throws -> NumpyArrayF {
        let data = try Data(contentsOf: url)

        // ── 1. マジック & バージョン確認 ──
        let magic: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59] // \x93NUMPY
        guard data.count > 10,
              Array(data[0..<6]) == magic
        else { throw NumpyLoaderError.invalidFormat }

        let major = data[6]
        let minor = data[7]

        // v1.0 / v2.0 だけ対応（ヘッダ長の取り方が違う）
        let headerLen: Int
        var headerOffset = 0
        switch major {
        case 1:
            headerLen = Int(UInt16(littleEndian: data[8..<10].withUnsafeBytes { $0.load(as: UInt16.self) }))
            headerOffset = 10
        case 2:
            headerLen = Int(UInt32(littleEndian: data[8..<12].withUnsafeBytes { $0.load(as: UInt32.self) }))
            headerOffset = 12
        default:
            throw NumpyLoaderError.unsupportedVersion
        }

        guard data.count >= headerOffset + headerLen else {
            throw NumpyLoaderError.invalidHeader
        }

        // ── 2. ヘッダ文字列を解析 ──
        let headerData = data[headerOffset ..< headerOffset + headerLen]
        guard let headerStr = String(data: headerData, encoding: .ascii) else {
            throw NumpyLoaderError.invalidHeader
        }

        // dtype チェック（float32 前提）
        guard headerStr.contains("'descr': '<f4'") || headerStr.contains("\"descr\": \"<f4\"") else {
            throw NumpyLoaderError.unsupportedDtype
        }

        // shape 抜き出し（"shape": (634, 768) みたいなのをパース）
        guard let shapeRangeStart = headerStr.range(of: "shape") else {
            throw NumpyLoaderError.invalidHeader
        }
        guard let parenOpen = headerStr[shapeRangeStart.lowerBound...].firstIndex(of: "("),
              let parenClose = headerStr[shapeRangeStart.lowerBound...].firstIndex(of: ")") else {
            throw NumpyLoaderError.invalidHeader
        }

        let inside = headerStr[headerStr.index(after: parenOpen)..<parenClose]
        let dims = inside
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { Int($0) }

        guard !dims.isEmpty else { throw NumpyLoaderError.invalidHeader }

        // ── 3. データ領域を Float32 で読み込む ──
        let dataStart = headerOffset + headerLen
        let elemCount = dims.reduce(1, *)

        let bytesPerElem = MemoryLayout<Float32>.size
        let neededBytes = elemCount * bytesPerElem
        guard data.count >= dataStart + neededBytes else {
            throw NumpyLoaderError.sizeMismatch
        }

        let body = data[dataStart ..< dataStart + neededBytes]

        let floats: [Float] = body.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: Float32.self)
            return Array(ptr)
        }

        guard floats.count == elemCount else {
            throw NumpyLoaderError.sizeMismatch
        }

        return NumpyArrayF(shape: dims, data: floats)
    }
}
