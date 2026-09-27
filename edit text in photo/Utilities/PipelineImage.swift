import CoreGraphics

/// Wraps a `CGImage` so it can cross an await/actor boundary.
///
/// `CGImage` instances are immutable after creation and safe to read concurrently, but the type
/// isn't reliably `Sendable` across SDK versions, so pipeline code passes this wrapper instead of
/// a raw `CGImage` whenever an image needs to travel between actors (e.g. into a `Task.detached`).
struct PipelineImage: @unchecked Sendable {
    let cgImage: CGImage
}
