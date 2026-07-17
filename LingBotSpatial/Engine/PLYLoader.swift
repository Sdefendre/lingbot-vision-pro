import Foundation
import simd

/// Minimal ASCII/binary-lite PLY loader for point clouds exported from LingBot-Map.
/// Expected properties: x y z [red green blue | r g b] [confidence|nx…]
enum PLYLoader {
    enum PLYError: Error, LocalizedError {
        case unreadable
        case missingHeader
        case unsupported
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not read PLY file"
            case .missingHeader: return "Invalid PLY header"
            case .unsupported: return "Only ASCII PLY with x y z is supported in this demo"
            case .empty: return "PLY contained no vertices"
            }
        }
    }

    static func load(url: URL) throws -> [ReconPoint] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PLYError.unreadable
        }
        return try parseASCII(text)
    }

    static func parseASCII(_ text: String) throws -> [ReconPoint] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "ply" else {
            throw PLYError.missingHeader
        }

        var vertexCount = 0
        var headerEnd = 0
        var formatASCII = false
        var properties: [String] = []

        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("format ascii") { formatASCII = true }
            if line.hasPrefix("element vertex") {
                let parts = line.split(separator: " ")
                if let last = parts.last, let n = Int(last) { vertexCount = n }
            }
            if line.hasPrefix("property") {
                let parts = line.split(separator: " ")
                if let name = parts.last { properties.append(String(name)) }
            }
            if line == "end_header" {
                headerEnd = idx
                break
            }
        }

        guard formatASCII else { throw PLYError.unsupported }
        guard vertexCount > 0 else { throw PLYError.empty }

        let xi = properties.firstIndex(of: "x") ?? 0
        let yi = properties.firstIndex(of: "y") ?? 1
        let zi = properties.firstIndex(of: "z") ?? 2
        let ri = properties.firstIndex(of: "red") ?? properties.firstIndex(of: "r")
        let gi = properties.firstIndex(of: "green") ?? properties.firstIndex(of: "g")
        let bi = properties.firstIndex(of: "blue") ?? properties.firstIndex(of: "b")
        let ci = properties.firstIndex(of: "confidence") ?? properties.firstIndex(of: "conf")

        var points: [ReconPoint] = []
        points.reserveCapacity(vertexCount)

        let start = headerEnd + 1
        let end = min(start + vertexCount, lines.count)
        for i in start..<end {
            let parts = lines[i].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count > zi,
                  let x = Float(parts[xi]),
                  let y = Float(parts[yi]),
                  let z = Float(parts[zi]) else { continue }

            var color = SIMD3<Float>(0.7, 0.7, 0.7)
            if let ri, let gi, let bi, parts.count > bi {
                let r = Float(parts[ri]) ?? 180
                let g = Float(parts[gi]) ?? 180
                let b = Float(parts[bi]) ?? 180
                // Accept 0–1 or 0–255
                let scale: Float = r > 1.5 || g > 1.5 || b > 1.5 ? 255 : 1
                color = SIMD3(r / scale, g / scale, b / scale)
            }

            var conf: Float = 0.8
            if let ci, parts.count > ci, let c = Float(parts[ci]) {
                conf = c
            }

            points.append(ReconPoint(position: SIMD3(x, y, z), color: color, confidence: conf))
        }

        if points.isEmpty { throw PLYError.empty }
        return points
    }

    /// Write a simple ASCII PLY for round-tripping demo exports.
    static func exportASCII(points: [ReconPoint], to url: URL) throws {
        var out = "ply\nformat ascii 1.0\n"
        out += "element vertex \(points.count)\n"
        out += "property float x\nproperty float y\nproperty float z\n"
        out += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        out += "property float confidence\nend_header\n"
        for p in points {
            let r = Int(min(max(p.color.x, 0), 1) * 255)
            let g = Int(min(max(p.color.y, 0), 1) * 255)
            let b = Int(min(max(p.color.z, 0), 1) * 255)
            out += "\(p.position.x) \(p.position.y) \(p.position.z) \(r) \(g) \(b) \(p.confidence)\n"
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }
}
