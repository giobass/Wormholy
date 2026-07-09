// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import WormholySwift

@MainActor
final class WebSocketInterceptorTests: XCTestCase {
    override func tearDown() async throws {
        Wormholy.setWebSocketEnabled(false)
        Wormholy.ignoredHosts = []
        Storage.shared.clearWebSocketConnections()
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

        XCTAssertEqual(task.wormholyModel?.url, url.absoluteString)
        XCTAssertEqual(task.wormholyModel?.host, url.host)

        await Task.yield()
        XCTAssertTrue(Storage.shared.webSocketConnections.contains { $0.id == task.wormholyModel?.id })
    }

    func testFactoryRequestOverloadCapturesHeaders() {
        Wormholy.setWebSocketEnabled(true)

        var request = URLRequest(url: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.webSocketTask(with: request)

        XCTAssertEqual(task.wormholyModel?.requestHeaders["Authorization"], "Bearer token")
    }

    func testFactoryProtocolsOverloadCapturesRequestedProtocols() {
        Wormholy.setWebSocketEnabled(true)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url, protocols: ["chat", "superchat"])

        XCTAssertEqual(task.wormholyModel?.requestedProtocols, ["chat", "superchat"])
    }

    func testDisabledInterceptorDoesNotAttachModel() {
        Wormholy.setWebSocketEnabled(false)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        XCTAssertNil(task.wormholyModel)
    }

    func testIgnoredHostDoesNotAttachModel() {
        Wormholy.setWebSocketEnabled(true)
        Wormholy.ignoredHosts = ["example.com"]

        let url = URL(string: "wss://api.example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        XCTAssertNil(task.wormholyModel)
    }

    func testNonIgnoredHostStillAttachesModel() {
        Wormholy.setWebSocketEnabled(true)
        Wormholy.ignoredHosts = ["example.com"]

        let url = URL(string: "wss://other.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        XCTAssertNotNil(task.wormholyModel)
    }
}
