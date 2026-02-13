import Testing
@testable import SwipeyLib

@Suite("ZoomToggleStateMachine Tests")
struct ZoomToggleStateMachineTests {

    // MARK: - Basic trigger detection

    @Test("Double-tap same Cmd key triggers expand")
    func sameSideDoubleTap() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.1) == .activated)
    }

    @Test("Left then right Cmd triggers expand")
    func leftThenRight() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.right), at: 0.1) == .activated)
    }

    @Test("Right then left Cmd triggers expand")
    func rightThenLeft() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.right), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.right), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.1) == .activated)
    }

    // MARK: - Rejection cases

    @Test("Non-modifier key between resets sequence")
    func nonModifierResets() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.nonModifierKey, at: 0.08) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.1) == nil)  // should NOT trigger
    }

    @Test("Timeout rejects second key")
    func timeoutRejects() {
        var sm = ZoomToggleStateMachine()
        #expect(sm.feed(.cmdDown(.left), at: 0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 0.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 0.5) == nil)  // 500ms > 400ms timeout
    }

    // MARK: - Hold vs toggle detection

    @Test("Quick release after activation signals hold-release")
    func quickRelease() {
        var sm = ZoomToggleStateMachine()
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.left), at: 0.1)
        // Release second key within 500ms of activation
        #expect(sm.feed(.cmdUp(.left), at: 0.3) == .holdReleased)
    }

    @Test("Slow release after activation signals toggle (no action)")
    func slowRelease() {
        var sm = ZoomToggleStateMachine()
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.left), at: 0.1)
        // Release second key after 500ms of activation
        #expect(sm.feed(.cmdUp(.left), at: 0.7) == nil)  // toggle mode, no action on release
    }

    // MARK: - Sequence after activation

    @Test("New sequence works after activation completes")
    func sequenceAfterActivation() {
        var sm = ZoomToggleStateMachine()
        // First activation
        _ = sm.feed(.cmdDown(.left), at: 0)
        _ = sm.feed(.cmdUp(.left), at: 0.05)
        _ = sm.feed(.cmdDown(.left), at: 0.1)
        _ = sm.feed(.cmdUp(.left), at: 0.7)  // slow release, toggle mode

        // Second activation (should work)
        #expect(sm.feed(.cmdDown(.left), at: 1.0) == nil)
        #expect(sm.feed(.cmdUp(.left), at: 1.05) == nil)
        #expect(sm.feed(.cmdDown(.left), at: 1.1) == .activated)
    }
}
