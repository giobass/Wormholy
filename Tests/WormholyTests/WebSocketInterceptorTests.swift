// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import XCTest
import Combine
@testable import WormholySwift

@MainActor
final class WebSocketInterceptorTests: XCTestCase {
    private final class SessionDelegate: NSObject, URLSessionDelegate {}
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() async throws {
        cancellables.removeAll()
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

    func testWebSocketEnabledStateIsSharedWithObjectiveCBridge() {
        Wormholy.setWebSocketEnabled(true)
        XCTAssertTrue(WHWebSocketRecorder.isEnabled)

        Wormholy.setWebSocketEnabled(false)
        XCTAssertFalse(WHWebSocketRecorder.isEnabled)
    }

    func testDelegateProxyRequiresWebSocketTrackingWhenSessionIsCreated() {
        Wormholy.setWebSocketEnabled(false)
        let disabledDelegate = SessionDelegate()
        let disabledSession = URLSession(configuration: .ephemeral,
                                         delegate: disabledDelegate,
                                         delegateQueue: nil)
        XCTAssertTrue(disabledSession.delegate === disabledDelegate)

        Wormholy.setWebSocketEnabled(true)
        let enabledDelegate = SessionDelegate()
        let enabledSession = URLSession(configuration: .ephemeral,
                                        delegate: enabledDelegate,
                                        delegateQueue: nil)
        XCTAssertFalse(enabledSession.delegate === enabledDelegate)
    }

    func testBackgroundFactoryAttachesAndPublishesModel() async {
        Wormholy.setWebSocketEnabled(true)
        let modelPublished = expectation(description: "background task model published")

        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
            let task = URLSession.shared.webSocketTask(with: url)

            DispatchQueue.main.async {
                XCTAssertEqual(task.wormholyModel?.url, url.absoluteString)
                XCTAssertTrue(Storage.shared.webSocketConnections.contains { $0.id == task.wormholyModel?.id })
                modelPublished.fulfill()
            }
        }

        await fulfillment(of: [modelPublished], timeout: 1)
    }

    func testRecorderKeepsLatestPendingMessagesWithinLimit() async throws {
        Wormholy.setWebSocketEnabled(true)
        Wormholy.webSocketMessageLimit = 2
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        let model = try XCTUnwrap(task.wormholyModel)
        let messagesRecorded = expectation(description: "latest messages recorded")

        model.$messages
            .dropFirst()
            .filter { $0.map(\.text) == ["second", "third"] }
            .prefix(1)
            .sink { _ in messagesRecorded.fulfill() }
            .store(in: &cancellables)

        WHWebSocketRecorder.recordSentText(task, text: "first")
        WHWebSocketRecorder.recordReceivedText(task, text: "second")
        WHWebSocketRecorder.recordSentText(task, text: "third")

        await fulfillment(of: [messagesRecorded], timeout: 1)
        XCTAssertEqual(model.messages.map(\.text), ["second", "third"])
    }

    func testConcurrentFactoryCallsAttachModels() {
        Wormholy.setWebSocketEnabled(true)
        let lock = NSLock()
        var tasks: [URLSessionWebSocketTask] = []

        DispatchQueue.concurrentPerform(iterations: 20) { index in
            let url = URL(string: "wss://example.com/socket/\(index)-\(UUID().uuidString)")!
            let task = URLSession.shared.webSocketTask(with: url)

            lock.lock()
            tasks.append(task)
            lock.unlock()
        }

        XCTAssertEqual(tasks.count, 20)
        XCTAssertTrue(tasks.allSatisfy { $0.wormholyModel != nil })
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
