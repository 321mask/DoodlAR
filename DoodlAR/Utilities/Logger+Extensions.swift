import os

/// Centralized os.Logger instances for DoodlAR subsystems.
/// Usage: `Logger.ml.info("Model loaded")`
extension Logger {
    private static let subsystem = "com.doodlar"

    /// Machine learning pipeline events (CoreML inference, model loading).
    static let ml = Logger(subsystem: subsystem, category: "ML")

    /// Augmented reality session events (anchors, scene mesh, tracking).
    static let ar = Logger(subsystem: subsystem, category: "AR")

    /// Vision framework events (rectangle detection, contour analysis).
    static let vision = Logger(subsystem: subsystem, category: "Vision")

    /// UI layer events (navigation, gestures, animations).
    static let ui = Logger(subsystem: subsystem, category: "UI")

    /// Camera feed and frame processing events.
    static let camera = Logger(subsystem: subsystem, category: "Camera")

    /// Data persistence events (SwiftData operations).
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// Audio playback events (spatial audio loading, playback).
    static let audio = Logger(subsystem: subsystem, category: "Audio")
}
