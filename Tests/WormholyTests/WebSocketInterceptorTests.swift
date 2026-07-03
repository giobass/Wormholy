import XCTest
@testable import WormholySwift

final class WebSocketInterceptorTests: XCTestCase {
    override func tearDown() async throws {
        Wormholy.setWebSocketEnabled(false)
        await MainActor.run { Storage.shared.clearWebSocketConnections() }
        try await super.tearDown()
    }

    func testInstallIsIdempotent() {
        WebSocketInterceptor.install()
        WebSocketInterceptor.install()
        // No crash on repeated install: swizzling only happens once.
    }

    func testFactoryURLOverloadAttachesModelWithoutNetworkActivity() async {
        Wormholy.setWebSocketEnabled(true)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)
        await waitForMainQueue()

        XCTAssertEqual(task.wormholyModel?.url, url.absoluteString)
        XCTAssertEqual(task.wormholyModel?.host, url.host)

        await MainActor.run {
            XCTAssertTrue(Storage.shared.webSocketConnections.contains { $0.id == task.wormholyModel?.id })
        }
    }

    func testFactoryRequestOverloadCapturesHeaders() async {
        Wormholy.setWebSocketEnabled(true)

        var request = URLRequest(url: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)

        XCTAssertEqual(task.wormholyModel?.requestHeaders["Authorization"], "Bearer token")
    }

    func testFactoryProtocolsOverloadCapturesRequestedProtocols() async {
        Wormholy.setWebSocketEnabled(true)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url, protocols: ["chat", "superchat"])
        await waitForMainQueue()

        XCTAssertEqual(task.wormholyModel?.requestedProtocols, ["chat", "superchat"])
    }

    private func waitForMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testDisabledInterceptorDoesNotAttachModel() {
        Wormholy.setWebSocketEnabled(false)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        XCTAssertNil(task.wormholyModel)
    }
}
