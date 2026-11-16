public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// macOS virtual key codes (Carbon `kVK_*`).
public enum KeyCode {
    public static let tab: UInt16 = 48
    public static let escape: UInt16 = 53
    public static let returnKey: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126
}

public enum KeyInput: Equatable, Sendable {
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool = false)
    case keyUp(keyCode: UInt16)
    case modifiersChanged(KeyModifiers)
}

/// Commands for a switcher that is already open.
public enum SwitcherCommand: Equatable, Sendable {
    case next
    case previous
    case up
    case down
    case cancel
    case commit
}

public enum KeyAction: Equatable, Sendable {
    case open(reverse: Bool)
    case command(SwitcherCommand)
}

public struct KeyDecision: Equatable, Sendable {
    public let action: KeyAction?
    public let consumesEvent: Bool

    public static let passThrough = KeyDecision(action: nil, consumesEvent: false)
    public static func open(reverse: Bool) -> KeyDecision {
        KeyDecision(action: .open(reverse: reverse), consumesEvent: true)
    }
    public static func consume(_ command: SwitcherCommand? = nil) -> KeyDecision {
        KeyDecision(action: command.map(KeyAction.command), consumesEvent: true)
    }
    public static func observe(_ command: SwitcherCommand) -> KeyDecision {
        KeyDecision(action: .command(command), consumesEvent: false)
    }
}

/// Bindings active while the switcher is open (Cmd held).
public enum SwitcherKeyBindings {
    struct Chord: Hashable {
        let keyCode: UInt16
        let shift: Bool
    }

    static let table: [Chord: SwitcherCommand] = [
        Chord(keyCode: KeyCode.tab, shift: false): .next,
        Chord(keyCode: KeyCode.tab, shift: true): .previous,
        Chord(keyCode: KeyCode.rightArrow, shift: false): .next,
        Chord(keyCode: KeyCode.leftArrow, shift: false): .previous,
        Chord(keyCode: KeyCode.upArrow, shift: false): .up,
        Chord(keyCode: KeyCode.downArrow, shift: false): .down,
        Chord(keyCode: KeyCode.escape, shift: false): .cancel,
        Chord(keyCode: KeyCode.returnKey, shift: false): .commit,
        Chord(keyCode: KeyCode.keypadEnter, shift: false): .commit,
    ]

    public static func command(keyCode: UInt16, shift: Bool) -> SwitcherCommand? {
        table[Chord(keyCode: keyCode, shift: shift)] ?? table[Chord(keyCode: keyCode, shift: false)]
    }
}

/// Decides which keyboard events open/drive the switcher and which pass through to apps.
public struct KeyRouter: Sendable {
    // Key-ups whose key-down we swallowed; apps must not see them either.
    private var swallowedKeyUps: Set<UInt16> = []

    public init() {}

    public mutating func route(_ input: KeyInput, isSwitching: Bool) -> KeyDecision {
        switch input {
        case let .keyDown(keyCode, modifiers, isRepeat):
            return routeKeyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, isSwitching: isSwitching)
        case let .keyUp(keyCode):
            return swallowedKeyUps.remove(keyCode) != nil ? .consume() : .passThrough
        case let .modifiersChanged(modifiers):
            return isSwitching && !modifiers.contains(.command) ? .observe(.commit) : .passThrough
        }
    }

    private mutating func routeKeyDown(keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool, isSwitching: Bool) -> KeyDecision {
        if isSwitching {
            guard modifiers.contains(.command) else {
                // Cmd release was missed (event tap briefly disabled): finish. A held key's repeats stay
                // swallowed; a fresh keystroke reaches the app.
                if isRepeat && swallowedKeyUps.contains(keyCode) {
                    return .consume(.commit)
                }
                swallowedKeyUps.remove(keyCode)
                return .observe(.commit)
            }
            // Unbound Cmd shortcuts are swallowed too, so e.g. Cmd+W can't hit the window behind the panel.
            swallowedKeyUps.insert(keyCode)
            return .consume(SwitcherKeyBindings.command(keyCode: keyCode, shift: modifiers.contains(.shift)))
        }
        // Auto-repeat of a key held through the switch must not leak into the newly activated app.
        if isRepeat && swallowedKeyUps.contains(keyCode) {
            return .consume()
        }
        guard keyCode == KeyCode.tab, modifiers.subtracting(.shift) == .command else {
            // A fresh press means any earlier swallowed press of this key has ended.
            swallowedKeyUps.remove(keyCode)
            return .passThrough
        }
        swallowedKeyUps.insert(keyCode)
        return .open(reverse: modifiers.contains(.shift))
    }
}
