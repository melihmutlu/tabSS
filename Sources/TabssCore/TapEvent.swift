import CoreGraphics

/// What the keyboard event tap needs from a raw `CGEvent`.
public enum TapEvent: Equatable, Sendable {
    case input(KeyInput)
    case tapDisabled

    public static let keyboardEventMask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
        .reduce(0) { $0 | (1 << $1.rawValue) }

    public init?(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            self = .input(.keyDown(keyCode: Self.keyCode(of: event), modifiers: KeyModifiers(event.flags), isRepeat: isRepeat))
        case .keyUp:
            self = .input(.keyUp(keyCode: Self.keyCode(of: event)))
        case .flagsChanged:
            self = .input(.modifiersChanged(KeyModifiers(event.flags)))
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            self = .tapDisabled
        default:
            return nil
        }
    }

    private static func keyCode(of event: CGEvent) -> UInt16 {
        UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }
}

extension KeyModifiers {
    /// Uses only device-independent masks; Caps Lock, fn and numeric-pad bits are ignored.
    public init(_ flags: CGEventFlags) {
        self = []
        if flags.contains(.maskCommand) { insert(.command) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskControl) { insert(.control) }
    }
}
