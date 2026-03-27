import CoreVideo

/// A `Sendable` wrapper around `CVPixelBuffer` for safe cross-actor transfer.
///
/// ARKit camera frames are backed by `IOSurface` and are thread-safe.
/// This wrapper enables passing them across actor boundaries without data race risks.
struct SendableFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}
