import XCTest

extension XCTestCase {
    /// Suspends until a previously-enqueued `DispatchQueue.main.async` block has run,
    /// letting tests observe state mutated asynchronously on the main queue (e.g.
    /// `WebSocketModel`'s `@Published` properties, all mutated via `DispatchQueue.main.async`).
    func waitForMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
