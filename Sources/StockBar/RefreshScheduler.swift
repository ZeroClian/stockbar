import Foundation

@MainActor protocol RefreshScheduling: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () async -> Void)
    func cancel()
}

/// Owned by AppStore for the entire application lifetime, never by the popover.
@MainActor final class RefreshScheduler: RefreshScheduling {
    private var timer: Timer?
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () async -> Void) {
        cancel()
        let next = Timer(timeInterval: max(0.01, delay), repeats: false) { _ in
            Task { @MainActor in await action() }
        }
        next.tolerance = min(1, max(0, delay * 0.05))
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
    func cancel() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
