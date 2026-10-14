import CoreGraphics
import Foundation
import Testing

import PiccoloCore

@testable import PiccoloSystem

@MainActor
private final class FakePresenter: HighlightPresenter {
    enum Call: Equatable {
        case present([CGRect])
        case dismiss
    }

    private(set) var calls: [Call] = []

    func present(_ frames: [CGRect]) {
        calls.append(.present(frames))
    }

    func dismiss() {
        calls.append(.dismiss)
    }
}

/// A planner the test controls: it answers what it is told to, and can be made to wait.
private final class Planner: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<[Destination], any Error> = .success([])
    private var gate: DispatchSemaphore?
    private(set) var actions: [Action] = []
    private(set) var settings: [ActionSettings] = []

    func answers(_ answer: Result<[Destination], any Error>) {
        lock.withLock { self.answer = answer }
    }

    /// From now on a plan waits until `open()`.
    func close() {
        lock.withLock { gate = DispatchSemaphore(value: 0) }
    }

    func open() {
        lock.withLock { gate }?.signal()
    }

    func plan(_ action: Action, _ settings: ActionSettings) throws -> [Destination] {
        let (gate, answer) = lock.withLock {
            actions.append(action)
            self.settings.append(settings)
            return (self.gate, self.answer)
        }
        gate?.wait()
        return try answer.get()
    }
}

private struct PlanFailure: Error {}

@MainActor
@Suite("Destination preview")
struct DestinationPreviewTests {
    private let presenter = FakePresenter()
    private let planner = Planner()
    private let preview: DestinationPreview
    private let left = Action.placeWindow(.preset(.leftHalf))
    private let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
    private let id = UUID()
    private let settings = ActionSettings(resizeStep: 0.1, gridFillOrder: .columns)

    init() {
        let planner = planner
        preview = DestinationPreview(
            presenter: presenter,
            queue: DispatchQueue(label: "test.destination-preview"),
            plan: { try planner.plan($0, $1) })
    }

    /// Waits until every plan that was asked for has been answered and dealt with.
    private func settle() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while preview.pendingPlans > 0 {
            guard ContinuousClock.now < deadline else {
                Issue.record("the planning did not finish: \(preview.pendingPlans) plan(s) pending")
                return
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    @Test("showing an action plans it on the queue and presents the frames; hiding dismisses them")
    func showAndHide() async throws {
        planner.answers(.success([Destination(frame: frame)]))

        preview.show(left, settings: settings, bindingID: id)
        try await settle()

        #expect(planner.actions == [left])
        #expect(planner.settings == [settings], "the plan is made with the settings given to show")
        #expect(presenter.calls == [.present([frame])])
        #expect(preview.isVisible)
        #expect(preview.frames == [frame])
        #expect(preview.windows == nil, "a single-window action lists no windows")
        #expect(preview.bindingID == id)

        preview.hide()
        #expect(presenter.calls == [.present([frame]), .dismiss])
        #expect(!preview.isVisible)
        #expect(preview.frames.isEmpty)
    }

    @Test("an arrangement lists the window of each frame, in the order of the frames")
    func windows() async throws {
        let second = CGRect(x: 400, y: 20, width: 300, height: 200)
        planner.answers(.success([
            Destination(frame: frame, window: WindowID(rawValue: 7)),
            Destination(frame: second, window: WindowID(rawValue: 5)),
        ]))

        preview.show(.arrangeGrid(GridSpec(count: 2, rows: 1, columns: 2)), settings: settings, bindingID: id)
        try await settle()

        #expect(preview.frames == [frame, second])
        #expect(preview.windows == [WindowID(rawValue: 7), WindowID(rawValue: 5)])
    }

    @Test("a release before the planning finished shows nothing")
    func hiddenBeforePlanned() async throws {
        planner.answers(.success([Destination(frame: frame)]))
        planner.close()

        preview.show(left, settings: settings, bindingID: id)
        preview.hide()
        planner.open()
        try await settle()

        #expect(presenter.calls.isEmpty, "the late plan was presented: \(presenter.calls)")
        #expect(!preview.isVisible)
    }

    @Test("a plan that is still running when another preview is asked for is dropped")
    func replacedBeforePlanned() async throws {
        let other = CGRect(x: 500, y: 500, width: 100, height: 100)
        planner.answers(.success([Destination(frame: frame)]))
        planner.close()
        preview.show(left, settings: settings, bindingID: id)

        preview.hide()
        planner.answers(.success([Destination(frame: other)]))
        preview.show(.placeWindow(.preset(.rightHalf)), settings: settings, bindingID: UUID())
        // Two plans wait behind the gate: the first one's, which is outdated, and the second one's.
        planner.open()
        planner.open()
        try await settle()

        #expect(presenter.calls == [.present([other])], "only the second plan may be presented")
    }

    @Test("a plan without a destination shows nothing")
    func nothingToShow() async throws {
        planner.answers(.success([]))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()

        #expect(presenter.calls.isEmpty)
        #expect(!preview.isVisible)
        #expect(preview.lastError == nil)
    }

    @Test("a planning error shows nothing and is remembered")
    func planningError() async throws {
        planner.answers(.failure(PlanFailure()))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()

        #expect(presenter.calls.isEmpty)
        #expect(!preview.isVisible)
        #expect(preview.lastError != nil)
    }

    @Test("hiding with nothing shown dismisses nothing")
    func hideNothing() {
        preview.hide()
        #expect(presenter.calls.isEmpty)
    }

    @Test("lastShowPresented tells whether the latest show reached the screen")
    func lastShowPresented() async throws {
        #expect(!preview.lastShowPresented)

        planner.answers(.success([Destination(frame: frame)]))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()
        preview.hide()
        #expect(preview.lastShowPresented, "it stays set after the hide, for whoever asks what the hold did")

        planner.answers(.success([]))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()
        #expect(!preview.lastShowPresented)

        planner.answers(.success([Destination(frame: frame)]))
        planner.close()
        preview.show(left, settings: settings, bindingID: id)
        preview.hide()
        planner.open()
        try await settle()
        #expect(!preview.lastShowPresented, "a plan that came too late was never presented")
    }

    @Test("showing again replaces what is shown")
    func showAgain() async throws {
        let other = CGRect(x: 500, y: 500, width: 100, height: 100)
        planner.answers(.success([Destination(frame: frame)]))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()

        planner.answers(.success([Destination(frame: other)]))
        preview.show(left, settings: settings, bindingID: id)
        try await settle()

        #expect(preview.frames == [other])
        #expect(presenter.calls.last == .present([other]))
    }
}
