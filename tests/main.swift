import Foundation
import simd

func ply(_ properties: String, _ row: String, suffix: String = "") -> String {
    "ply\nformat ascii 1.0\nelement vertex 1\n\(properties)\n\(suffix)end_header\n\(row)\n"
}

let name = CommandLine.arguments[1]
switch name {
case "pose":
    let pose = CameraPose(id: 1, frameIndex: 0, position: SIMD3<Float>(1, 2, 3),
                          rotation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
                          isKeyframe: true)
    let origin = pose.transform * SIMD4<Float>(0, 0, 0, 1)
    precondition(simd_length(origin - SIMD4<Float>(1, 2, 3, 1)) < 0.0001)
    let forward = pose.transform * SIMD4<Float>(0, 0, -1, 0)
    precondition(simd_length(SIMD3(forward.x, forward.y, forward.z) - pose.lookDirection) < 0.0001)
case "reordered":
    let points = try PLYLoader.parseASCII(ply("property float z\nproperty float y\nproperty float x", "3 2 1"))
    precondition(points[0].position == SIMD3<Float>(1, 2, 3))
case "short":
    do {
        _ = try PLYLoader.parseASCII(ply("property float z\nproperty float y\nproperty float x", "3"))
        fatalError("Malformed row accepted")
    } catch {}
case "missing-coordinates":
    do {
        _ = try PLYLoader.parseASCII(ply("property float a\nproperty float b\nproperty float c", "1 2 3"))
        fatalError("Missing coordinates accepted")
    } catch {}
case "missing-end":
    do {
        _ = try PLYLoader.parseASCII("ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\n1 2 3")
        fatalError("Incomplete header accepted")
    } catch PLYLoader.PLYError.missingHeader {
        // A truncated header must be diagnosed before attempting vertex parsing.
    } catch {
        fatalError("Wrong error for incomplete header: \(error)")
    }
case "dark-colors":
    let points = try PLYLoader.parseASCII(ply("property float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue", "1 2 3 1 0 1"))
    precondition(points[0].color == SIMD3<Float>(1 / 255, 0, 1 / 255))
case "element-scope":
    let points = try PLYLoader.parseASCII("ply\nformat ascii 1.0\nelement face 0\nproperty list uchar int vertex_indices\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1 2 3")
    precondition(points[0].position == SIMD3<Float>(1, 2, 3))
default: fatalError("Unknown case")
}
print("PASS: \(name)")
