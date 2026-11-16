import CoreGraphics
import Testing
@testable import TabssCore

struct TapEventTests {
    private func keyEvent(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags = [], autorepeat: Int64 = 0) throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down))
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat)
        return event
    }

    @Test func keyDownCarriesKeyCodeModifiersAndRepeat() throws {
        let event = try keyEvent(CGKeyCode(KeyCode.tab), down: true, flags: [.maskCommand, .maskShift], autorepeat: 1)
        #expect(TapEvent(type: .keyDown, event: event) == .input(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .shift], isRepeat: true)))
    }

    // KeyRouter relies on isRepeat to tell a fresh keystroke (delivered to apps) from a held key's repeat (swallowed).
    @Test func freshKeyDownIsNotARepeat() throws {
        let event = try keyEvent(0, down: true, flags: .maskCommand)
        #expect(TapEvent(type: .keyDown, event: event) == .input(.keyDown(keyCode: 0, modifiers: .command, isRepeat: false)))
    }

    // Releasing Cmd while Shift is still held (end of Cmd+Shift+Tab) must report Cmd as up so the router commits.
    @Test func commandReleaseWithShiftStillHeld() throws {
        let event = try keyEvent(56, down: false, flags: .maskShift)
        #expect(TapEvent(type: .flagsChanged, event: event) == .input(.modifiersChanged(.shift)))
    }

    @Test func keyUpAndFlagsChanged() throws {
        let event = try keyEvent(CGKeyCode(KeyCode.tab), down: false, flags: .maskCommand)
        #expect(TapEvent(type: .keyUp, event: event) == .input(.keyUp(keyCode: KeyCode.tab)))
        #expect(TapEvent(type: .flagsChanged, event: event) == .input(.modifiersChanged(.command)))
    }

    @Test func tapDisabledAndUnrelatedTypes() throws {
        let event = try keyEvent(0, down: true)
        #expect(TapEvent(type: .tapDisabledByTimeout, event: event) == .tapDisabled)
        #expect(TapEvent(type: .tapDisabledByUserInput, event: event) == .tapDisabled)
        #expect(TapEvent(type: .mouseMoved, event: event) == nil)
    }

    @Test func modifiersIgnoreCapsLockFnAndDeviceBits() {
        let flags: CGEventFlags = [.maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad, CGEventFlags(rawValue: 0x8)]
        #expect(KeyModifiers(flags) == .command)
        #expect(KeyModifiers([.maskAlternate, .maskControl]) == [.option, .control])
    }

    @Test func maskCoversExactlyKeyboardEvents() {
        let expected: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        #expect(TapEvent.keyboardEventMask == expected)
    }
}
