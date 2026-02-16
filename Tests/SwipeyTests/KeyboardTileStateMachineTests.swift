import Testing
@testable import SwipeyLib

@Suite("KeyboardTileStateMachine Tests")
struct KeyboardTileStateMachineTests {

    typealias SM = KeyboardTileStateMachine
    typealias Dir = SM.ArrowDirection

    // MARK: - From untiled

    @Test("Untiled: arrows tile to halves or maximize")
    func fromUntiled() {
        #expect(SM.transition(from: nil, direction: .left) == .leftHalf)
        #expect(SM.transition(from: nil, direction: .right) == .rightHalf)
        #expect(SM.transition(from: nil, direction: .up) == .maximize)
        #expect(SM.transition(from: nil, direction: .down) == nil)
    }

    // MARK: - From halves (subdivide to quarters)

    @Test("Left half: perpendicular arrows subdivide, right moves")
    func fromLeftHalf() {
        #expect(SM.transition(from: .leftHalf, direction: .up) == .topLeftQuarter)
        #expect(SM.transition(from: .leftHalf, direction: .down) == .bottomLeftQuarter)
        #expect(SM.transition(from: .leftHalf, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .leftHalf, direction: .left) == nil)
    }

    @Test("Right half: perpendicular arrows subdivide, left moves")
    func fromRightHalf() {
        #expect(SM.transition(from: .rightHalf, direction: .up) == .topRightQuarter)
        #expect(SM.transition(from: .rightHalf, direction: .down) == .bottomRightQuarter)
        #expect(SM.transition(from: .rightHalf, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .rightHalf, direction: .right) == nil)
    }

    @Test("Top half: perpendicular arrows subdivide, up maximizes")
    func fromTopHalf() {
        #expect(SM.transition(from: .topHalf, direction: .left) == .topLeftQuarter)
        #expect(SM.transition(from: .topHalf, direction: .right) == .topRightQuarter)
        #expect(SM.transition(from: .topHalf, direction: .up) == .maximize)
        #expect(SM.transition(from: .topHalf, direction: .down) == .bottomHalf)
    }

    @Test("Bottom half: perpendicular arrows subdivide, down restores")
    func fromBottomHalf() {
        #expect(SM.transition(from: .bottomHalf, direction: .left) == .bottomLeftQuarter)
        #expect(SM.transition(from: .bottomHalf, direction: .right) == .bottomRightQuarter)
        #expect(SM.transition(from: .bottomHalf, direction: .up) == .topHalf)
        #expect(SM.transition(from: .bottomHalf, direction: .down) == .restore)
    }

    // MARK: - From maximize

    @Test("Maximize: up goes fullscreen, down restores, sides go to halves")
    func fromMaximize() {
        #expect(SM.transition(from: .maximize, direction: .up) == .fullscreen)
        #expect(SM.transition(from: .maximize, direction: .down) == .restore)
        #expect(SM.transition(from: .maximize, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .maximize, direction: .right) == .rightHalf)
    }

    // MARK: - From fullscreen

    @Test("Fullscreen: only down restores, others are no-op")
    func fromFullscreen() {
        #expect(SM.transition(from: .fullscreen, direction: .down) == .restore)
        #expect(SM.transition(from: .fullscreen, direction: .up) == nil)
        #expect(SM.transition(from: .fullscreen, direction: .left) == nil)
        #expect(SM.transition(from: .fullscreen, direction: .right) == nil)
    }

    // MARK: - From quarters (slide + expand)

    @Test("Top-left quarter: slide right/down, expand left/up")
    func fromTopLeftQuarter() {
        #expect(SM.transition(from: .topLeftQuarter, direction: .right) == .topRightQuarter)
        #expect(SM.transition(from: .topLeftQuarter, direction: .down) == .bottomLeftQuarter)
        #expect(SM.transition(from: .topLeftQuarter, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .topLeftQuarter, direction: .up) == .topHalf)
    }

    @Test("Top-right quarter: slide left/down, expand right/up")
    func fromTopRightQuarter() {
        #expect(SM.transition(from: .topRightQuarter, direction: .left) == .topLeftQuarter)
        #expect(SM.transition(from: .topRightQuarter, direction: .down) == .bottomRightQuarter)
        #expect(SM.transition(from: .topRightQuarter, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .topRightQuarter, direction: .up) == .topHalf)
    }

    @Test("Bottom-left quarter: slide right/up, expand left/down")
    func fromBottomLeftQuarter() {
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .right) == .bottomRightQuarter)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .up) == .topLeftQuarter)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .left) == .leftHalf)
        #expect(SM.transition(from: .bottomLeftQuarter, direction: .down) == .bottomHalf)
    }

    @Test("Bottom-right quarter: slide left/up, expand right/down")
    func fromBottomRightQuarter() {
        #expect(SM.transition(from: .bottomRightQuarter, direction: .left) == .bottomLeftQuarter)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .up) == .topRightQuarter)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .right) == .rightHalf)
        #expect(SM.transition(from: .bottomRightQuarter, direction: .down) == .bottomHalf)
    }

    // MARK: - Multi-step sequences

    @Test("Untiled -> left half -> top-left quarter (two-step quarter tiling)")
    func twoStepQuarterTile() {
        let step1 = SM.transition(from: nil, direction: .left)
        #expect(step1 == .leftHalf)
        let step2 = SM.transition(from: step1, direction: .up)
        #expect(step2 == .topLeftQuarter)
    }

    @Test("Untiled -> maximize -> fullscreen (two-step fullscreen)")
    func twoStepFullscreen() {
        let step1 = SM.transition(from: nil, direction: .up)
        #expect(step1 == .maximize)
        let step2 = SM.transition(from: step1, direction: .up)
        #expect(step2 == .fullscreen)
    }

    @Test("Navigate all four quarters clockwise from top-left")
    func quarterNavigation() {
        var pos: TilePosition? = .topLeftQuarter
        pos = SM.transition(from: pos, direction: .right)
        #expect(pos == .topRightQuarter)
        pos = SM.transition(from: pos, direction: .down)
        #expect(pos == .bottomRightQuarter)
        pos = SM.transition(from: pos, direction: .left)
        #expect(pos == .bottomLeftQuarter)
        pos = SM.transition(from: pos, direction: .up)
        #expect(pos == .topLeftQuarter)
    }
}
