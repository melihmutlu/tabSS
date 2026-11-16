import Testing
@testable import TabssCore

struct KeyRouterTests {
    private var router = KeyRouter()

    @Test mutating func cmdTabOpensAndIsSwallowed() {
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false) == .open(reverse: false))
    }

    @Test mutating func cmdShiftTabOpensReversed() {
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .shift]), isSwitching: false) == .open(reverse: true))
    }

    @Test mutating func otherCombinationsPassThroughWhenIdle() {
        let inputs: [KeyInput] = [
            .keyDown(keyCode: KeyCode.tab, modifiers: []),
            .keyDown(keyCode: KeyCode.tab, modifiers: [.command, .option]),
            .keyDown(keyCode: KeyCode.tab, modifiers: [.command, .control]),
            .keyDown(keyCode: 12, modifiers: .command),
            .keyUp(keyCode: 12),
            .modifiersChanged([]),
        ]
        for input in inputs {
            #expect(router.route(input, isSwitching: false) == .passThrough)
        }
    }

    @Test mutating func navigationWhileSwitching() {
        let expectations: [(UInt16, KeyModifiers, SwitcherCommand?)] = [
            (KeyCode.tab, .command, .next),
            (KeyCode.tab, [.command, .shift], .previous),
            (KeyCode.rightArrow, .command, .next),
            (KeyCode.leftArrow, [.command, .shift], .previous),
            (KeyCode.escape, .command, .cancel),
            (KeyCode.returnKey, .command, .commit),
            (KeyCode.keypadEnter, .command, .commit),
            (12, .command, nil),
        ]
        for (keyCode, modifiers, command) in expectations {
            #expect(router.route(.keyDown(keyCode: keyCode, modifiers: modifiers), isSwitching: true) == .consume(command))
        }
    }

    @Test mutating func releasingCommandCommitsWithoutSwallowingFlagsEvent() {
        #expect(router.route(.modifiersChanged([]), isSwitching: true) == .observe(.commit))
        #expect(router.route(.modifiersChanged(.shift), isSwitching: true) == .observe(.commit))
        #expect(router.route(.modifiersChanged(.command), isSwitching: true) == .passThrough)
    }

    @Test mutating func keyDownWithoutCommandWhileSwitchingCommitsAndPassesThrough() {
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: []), isSwitching: true) == .observe(.commit))
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .passThrough)
    }

    @Test mutating func keyUpOfSwallowedKeyDownIsSwallowedAfterSwitchEnds() {
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        _ = router.route(.modifiersChanged([]), isSwitching: true)
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .consume())
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .passThrough)
    }

    @Test mutating func keyUpOfKeyHeldBeforeOpeningPassesThrough() {
        #expect(router.route(.keyUp(keyCode: 12), isSwitching: true) == .passThrough)
    }

    @Test mutating func switcherKeysPassThroughWhenIdle() {
        for keyCode in [KeyCode.escape, KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.returnKey, KeyCode.keypadEnter] {
            #expect(router.route(.keyDown(keyCode: keyCode, modifiers: .command), isSwitching: false) == .passThrough)
            #expect(router.route(.keyUp(keyCode: keyCode), isSwitching: false) == .passThrough)
        }
    }

    @Test mutating func shiftFallsBackToUnshiftedBindingWhileSwitching() {
        let expectations: [(UInt16, SwitcherCommand)] = [
            (KeyCode.rightArrow, .next),
            (KeyCode.escape, .cancel),
            (KeyCode.returnKey, .commit),
            (KeyCode.keypadEnter, .commit),
        ]
        for (keyCode, command) in expectations {
            #expect(router.route(.keyDown(keyCode: keyCode, modifiers: [.command, .shift]), isSwitching: true) == .consume(command))
        }
    }

    @Test mutating func optionAndControlDoNotChangeBindingsWhileSwitching() {
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .option]), isSwitching: true) == .consume(.next))
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [.command, .control, .shift]), isSwitching: true) == .consume(.previous))
    }

    @Test mutating func escapeWithoutCommandWhileSwitchingCommitsRatherThanCancels() {
        // A missing Cmd flag means the release was missed, so the user already intended to commit.
        #expect(router.route(.keyDown(keyCode: KeyCode.escape, modifiers: []), isSwitching: true) == .observe(.commit))
    }

    @Test mutating func unboundKeyPressedWhileSwitchingHasItsKeyUpSwallowedAfterSwitchEnds() {
        let q: UInt16 = 12
        #expect(router.route(.keyDown(keyCode: q, modifiers: .command), isSwitching: true) == .consume())
        #expect(router.route(.keyUp(keyCode: q), isSwitching: false) == .consume())
        #expect(router.route(.keyUp(keyCode: q), isSwitching: false) == .passThrough)
    }

    @Test mutating func autoRepeatedKeyDownsSwallowOnlyOneKeyUp() {
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        for _ in 0..<3 {
            #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: true) == .consume(.next))
        }
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .consume())
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .passThrough)
    }

    @Test mutating func passThroughKeyDownUpPairIsNeverSplit() {
        // Cmd+Tab's key-up never reached us (e.g. the tap was briefly disabled). A later plain Tab press passes
        // through, so its key-up must pass through too, or the app sees a key-down with no matching key-up.
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: []), isSwitching: false) == .passThrough)
        let keyUp = router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false)
        #expect(keyUp == .passThrough)
    }

    @Test mutating func modifierChangesWhileHoldingCommandDoNotCommit() {
        #expect(router.route(.modifiersChanged([.command, .shift]), isSwitching: true) == .passThrough)
        #expect(router.route(.modifiersChanged([.command, .option, .control]), isSwitching: true) == .passThrough)
        #expect(router.route(.modifiersChanged([.option]), isSwitching: true) == .observe(.commit))
    }

    @Test mutating func freshPressOfAnotherKeyKeepsPendingTabKeyUpSwallowed() {
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        _ = router.route(.modifiersChanged([]), isSwitching: true)
        #expect(router.route(.keyDown(keyCode: 12, modifiers: []), isSwitching: false) == .passThrough)
        #expect(router.route(.keyUp(keyCode: 12), isSwitching: false) == .passThrough)
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .consume())
    }

    @Test mutating func passedThroughKeyDownWhileSwitchingKeepsItsKeyUp() {
        // Cmd release was missed and a fresh Tab press arrives: it reaches the app,
        // so its key-up must too, or the app sees a key-down with no matching key-up.
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: []), isSwitching: true) == .observe(.commit))
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .passThrough)
    }

    @Test mutating func autoRepeatOfKeyHeldThroughCommitIsSwallowed() {
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        _ = router.route(.modifiersChanged([]), isSwitching: true)
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [], isRepeat: true), isSwitching: false) == .consume())
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [], isRepeat: true), isSwitching: false) == .consume())
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .consume())
    }

    @Test mutating func autoRepeatOfUnrelatedKeyPassesThrough() {
        #expect(router.route(.keyDown(keyCode: 12, modifiers: [], isRepeat: true), isSwitching: false) == .passThrough)
    }

    @Test mutating func autoRepeatAfterMissedCommandReleaseDoesNotLeakIntoApp() {
        // Cmd's flags-changed event was lost while Tab stayed held; the repeats must not type Tabs into the app.
        _ = router.route(.keyDown(keyCode: KeyCode.tab, modifiers: .command), isSwitching: false)
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [], isRepeat: true), isSwitching: true) == .consume(.commit))
        #expect(router.route(.keyDown(keyCode: KeyCode.tab, modifiers: [], isRepeat: true), isSwitching: false) == .consume())
        #expect(router.route(.keyUp(keyCode: KeyCode.tab), isSwitching: false) == .consume())
    }
}
