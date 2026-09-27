import Foundation
import simd

/// ASCII PLY loader for point clouds exported from LingBot-Map.
/// Expected vertex properties: x y z [red green blue | r g b] [confidence|conf]
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
        var headerEnd: Int?
        var formatASCII = false
        var properties: [String] = []
        var propertyTypes: [String] = []
        var currentElement: String?
        var sawVertices = false

        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if parts == ["format", "ascii", "1.0"] { formatASCII = true }
            if parts.first == "element" {
                guard parts.count == 3, let count = Int(parts[2]), count >= 0 else {
                    throw PLYError.missingHeader
                }
                currentElement = parts[1]
                if currentElement == "vertex" {
                    guard !sawVertices else { throw PLYError.unsupported }
                    sawVertices = true
                    vertexCount = count
                } else if !sawVertices && count > 0 {
                    // Vertex rows must be first; do not mistake another element's
                    // payload for coordinates.
                    throw PLYError.unsupported
                }
            }
            if parts.first == "property", currentElement == "vertex" {
                guard parts.count == 3, parts[1] != "list" else {
                    throw PLYError.unsupported
                }
                propertyTypes.append(parts[1])
                properties.append(parts[2])
            }
            if line == "end_header" {
                headerEnd = idx
                break
            }
        }

        guard let headerEnd else { throw PLYError.missingHeader }
        guard formatASCII else { throw PLYError.unsupported }
        guard vertexCount > 0 else { throw PLYError.empty }

        guard let xi = properties.firstIndex(of: "x"),
              let yi = properties.firstIndex(of: "y"),
              let zi = properties.firstIndex(of: "z") else {
            throw PLYError.unsupported
        }
        let ri = properties.firstIndex(of: "red") ?? properties.firstIndex(of: "r")
        let gi = properties.firstIndex(of: "green") ?? properties.firstIndex(of: "g")
        let bi = properties.firstIndex(of: "blue") ?? properties.firstIndex(of: "b")
        let ci = properties.firstIndex(of: "confidence") ?? properties.firstIndex(of: "conf")

        var points: [ReconPoint] = []
        let start = headerEnd + 1
        guard vertexCount <= lines.count - start else { throw PLYError.unreadable }
        points.reserveCapacity(vertexCount)

        let end = start + vertexCount
        for i in start..<end {
            let parts = lines[i].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= properties.count,
                  let x = Float(parts[xi]),
                  let y = Float(parts[yi]),
                  let z = Float(parts[zi]),
                  x.isFinite, y.isFinite, z.isFinite else { throw PLYError.unreadable }

            var color = SIMD3<Float>(0.7, 0.7, 0.7)
            if let ri, let gi, let bi {
                guard let r = Float(parts[ri]), let g = Float(parts[gi]),
                      let b = Float(parts[bi]), r.isFinite, g.isFinite, b.isFinite else {
                    throw PLYError.unreadable
                }
                // Byte properties stay in byte range even for very dark colors.
                let byteColor = [ri, gi, bi].allSatisfy {
                    ["uchar", "uint8"].contains(propertyTypes[$0])
                }
                let scale: Float = byteColor || r > 1.5 || g > 1.5 || b > 1.5 ? 255 : 1
                color = simd_clamp(SIMD3(r / scale, g / scale, b / scale),
                                   SIMD3(repeating: 0), SIMD3(repeating: 1))
            }

            var conf: Float = 0.8
            if let ci {
                guard let c = Float(parts[ci]), c.isFinite else { throw PLYError.unreadable }
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
