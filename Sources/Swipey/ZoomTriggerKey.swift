import CoreGraphics
import Foundation

enum ZoomTriggerKey: String, CaseIterable, Sendable {
    case cmd = "cmd"
    case control = "control"
    case option = "option"

    var displayName: String {
        switch self {
        case .cmd: "Command"
        case .control: "Control"
        case .option: "Option"
        }
    }

    var symbol: String {
        switch self {
        case .cmd: "\u{2318}"
        case .control: "\u{2303}"
        case .option: "\u{2325}"
        }
    }

    var leftKeycode: Int64 {
        switch self {
        case .cmd: 0x37      // kVK_Command
        case .control: 0x3B  // kVK_Control
        case .option: 0x3A   // kVK_Option
        }
    }

    var rightKeycode: Int64 {
        switch self {
        case .cmd: 0x36      // kVK_RightCommand
        case .control: 0x3E  // kVK_RightControl
        case .option: 0x3D   // kVK_RightOption
        }
    }

    var flagMask: CGEventFlags {
        switch self {
        case .cmd: .maskCommand
        case .control: .maskControl
        case .option: .maskAlternate
        }
    }

    static var current: ZoomTriggerKey {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "zoomTriggerKey"),
                  let key = ZoomTriggerKey(rawValue: raw) else { return .cmd }
            return key
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "zoomTriggerKey")
        }
    }
}
