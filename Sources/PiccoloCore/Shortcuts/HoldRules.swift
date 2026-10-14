import Foundation

/// What a shortcut does while it is held, as a state machine: events in, effects out.
///
/// With the destination preview off, a press runs its action at once, as it always did. With it on,
/// a press starts a hold: the action runs when the shortcut is released, and while it is held for
/// longer than ``delay`` a preview shows where the windows will go. Escape cancels the hold.
///
/// The machine knows nothing about time, keys or windows. It asks for a timer with
/// ``Effect/startTimer(_:)`` and is told that the timer fired with ``Event/timerFired(_:)``; the token
/// of the request comes back with the answer, so that the timer of a hold that is over cannot show
/// the preview of the next one. ``HoldController`` runs it against a real timer.
///
/// The rules:
///
/// - Preview off: a press runs, and releases are ignored.
/// - Preview on: a press starts a hold and asks for the timer. A release before the timer fired is a
///   tap: it runs the action and nothing is shown. When the timer fires with the shortcut still held,
///   the preview is shown; the release then hides it and runs the action.
/// - Escape while a shortcut is held cancels it: the preview is hidden if it was shown, and the release
///   then does nothing. The shortcut stays held until it is released, so that its auto-repeat is not
///   mistaken for a new press.
/// - A repeated press of the held shortcut is ignored. A press of another shortcut cancels the held one
///   (no action) and takes over. A release of a shortcut that is not the held one is ignored.
/// - Cancel-all (the hotkeys were suspended or replaced, the preview was switched off) hides the
///   preview and drops the held shortcut without running it.
public struct HoldRules: Equatable, Sendable {
    /// How long a shortcut has to be held before its preview shows, in seconds.
    public static let delay: TimeInterval = 0.2

    /// What happened.
    public enum Event: Equatable, Sendable {
        /// The shortcut of binding `id` went down. Auto-repeat, if the system sends it, is more of these.
        case press(UUID)
        /// The shortcut of binding `id` went up.
        case release(UUID)
        /// Escape went down while a shortcut was held. Only meaningful then.
        case escape
        /// The timer asked for with `startTimer(token)` fired.
        case timerFired(Int)
        /// Everything in flight is void: hotkeys were released or replaced, or the setting changed.
        case cancelAll
    }

    /// What the caller has to do, in order.
    public enum Effect: Equatable, Sendable {
        /// Run the action of binding `id`.
        case run(UUID)
        /// Show the preview for binding `id`.
        case showPreview(UUID)
        /// Hide the preview.
        case hidePreview
        /// Call back with `timerFired(token)` after ``HoldRules/delay`` seconds.
        case startTimer(Int)
    }

    /// Where a hold is.
    public enum Phase: Equatable, Sendable {
        /// Pressed, the timer has not fired.
        case waiting
        /// The timer fired and the preview was asked for.
        case previewing
        /// Escape cancelled it. Still held, until the release.
        case cancelled
    }

    /// The shortcut that is down.
    public struct Held: Equatable, Sendable {
        public var id: UUID
        public var phase: Phase
        /// Whether the preview was asked for during this hold, also when Escape has hidden it since.
        public var previewShown: Bool
        var token: Int
    }

    /// How a hold ended.
    public enum Result: String, Equatable, Sendable {
        /// The action was run.
        case ran
        /// It was not: Escape, another shortcut or a cancel-all came first.
        case cancelled
    }

    /// What became of the last hold (or of the last press with the preview off).
    public struct Outcome: Equatable, Sendable {
        public var id: UUID
        public var result: Result
        public var previewShown: Bool

        public init(id: UUID, result: Result, previewShown: Bool) {
            self.id = id
            self.result = result
            self.previewShown = previewShown
        }
    }

    /// Whether a held shortcut waits for its release. Change it with ``setPreviewEnabled(_:)``, which
    /// also cancels what is held.
    public var isPreviewEnabled: Bool
    /// The shortcut that is down, or `nil`.
    public private(set) var held: Held?
    /// What became of the last hold; `nil` before the first.
    public private(set) var last: Outcome?
    private var nextToken = 1

    public init(isPreviewEnabled: Bool) {
        self.isPreviewEnabled = isPreviewEnabled
    }

    /// Sets ``isPreviewEnabled``. Switching it off while something is held cancels that, as
    /// ``Event/cancelAll`` does, and the effects say what to undo.
    public mutating func setPreviewEnabled(_ enabled: Bool) -> [Effect] {
        guard enabled != isPreviewEnabled else { return [] }
        isPreviewEnabled = enabled
        return enabled ? [] : handle(.cancelAll)
    }

    /// Takes an event and answers what to do about it.
    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .press(let id): press(id)
        case .release(let id): release(id)
        case .escape: escape()
        case .timerFired(let token): timerFired(token)
        case .cancelAll: cancelAll()
        }
    }

    // MARK: Events

    private mutating func press(_ id: UUID) -> [Effect] {
        guard isPreviewEnabled else {
            // A hold that outlived the setting is dropped before the action runs.
            let undo = cancelAll()
            last = Outcome(id: id, result: .ran, previewShown: false)
            return undo + [.run(id)]
        }
        if let held, held.id == id {
            return []
        }
        let undo = cancelAll()
        let token = nextToken
        nextToken += 1
        held = Held(id: id, phase: .waiting, previewShown: false, token: token)
        return undo + [.startTimer(token)]
    }

    private mutating func release(_ id: UUID) -> [Effect] {
        guard let held, held.id == id else { return [] }
        self.held = nil
        switch held.phase {
        case .waiting:
            last = Outcome(id: id, result: .ran, previewShown: false)
            return [.run(id)]
        case .previewing:
            last = Outcome(id: id, result: .ran, previewShown: true)
            return [.hidePreview, .run(id)]
        case .cancelled:
            return []
        }
    }

    private mutating func escape() -> [Effect] {
        guard var held, held.phase != .cancelled else { return [] }
        let hide: [Effect] = held.phase == .previewing ? [.hidePreview] : []
        held.phase = .cancelled
        self.held = held
        last = Outcome(id: held.id, result: .cancelled, previewShown: held.previewShown)
        return hide
    }

    private mutating func timerFired(_ token: Int) -> [Effect] {
        guard var held, held.token == token, held.phase == .waiting else { return [] }
        held.phase = .previewing
        held.previewShown = true
        self.held = held
        return [.showPreview(held.id)]
    }

    private mutating func cancelAll() -> [Effect] {
        guard let held else { return [] }
        self.held = nil
        // A hold that Escape cancelled has its outcome already.
        if held.phase != .cancelled {
            last = Outcome(id: held.id, result: .cancelled, previewShown: held.previewShown)
        }
        return held.phase == .previewing ? [.hidePreview] : []
    }
}
