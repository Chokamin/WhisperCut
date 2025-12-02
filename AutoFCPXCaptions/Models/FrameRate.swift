import Foundation

/// Frame rate options for FCPXML generation
/// The timescale is crucial for accurate timecode conversion
enum FrameRate: String, CaseIterable, Identifiable {
    case fps23_98 = "23.98 fps"
    case fps24 = "24 fps"
    case fps25 = "25 fps"
    case fps29_97 = "29.97 fps"
    case fps30 = "30 fps"
    case fps50 = "50 fps"
    case fps59_94 = "59.94 fps"
    case fps60 = "60 fps"

    var id: String { rawValue }

    /// Timescale used in FCPXML for rational time calculations
    /// Formula: value = seconds * timescale
    var timescale: Int {
        switch self {
        case .fps23_98: return 24000
        case .fps24: return 2400
        case .fps25: return 2500
        case .fps29_97: return 30000
        case .fps30: return 3000
        case .fps50: return 5000
        case .fps59_94: return 60000
        case .fps60: return 6000
        }
    }

    /// Frame duration as FCPXML rational time string
    var frameDuration: String {
        switch self {
        case .fps23_98: return "1001/24000s"
        case .fps24: return "100/2400s"
        case .fps25: return "100/2500s"
        case .fps29_97: return "1001/30000s"
        case .fps30: return "100/3000s"
        case .fps50: return "100/5000s"
        case .fps59_94: return "1001/60000s"
        case .fps60: return "100/6000s"
        }
    }

    /// Frames per second as a Double value
    var fps: Double {
        switch self {
        case .fps23_98: return 24000.0 / 1001.0
        case .fps24: return 24.0
        case .fps25: return 25.0
        case .fps29_97: return 30000.0 / 1001.0
        case .fps30: return 30.0
        case .fps50: return 50.0
        case .fps59_94: return 60000.0 / 1001.0
        case .fps60: return 60.0
        }
    }

    /// Convert seconds to FCPXML rational time string
    func toRationalTime(_ seconds: TimeInterval) -> String {
        let value = Int(round(seconds * Double(timescale)))
        return "\(value)/\(timescale)s"
    }

    /// Duration of a single frame in seconds
    var frameDurationSeconds: TimeInterval {
        1.0 / fps
    }
}
