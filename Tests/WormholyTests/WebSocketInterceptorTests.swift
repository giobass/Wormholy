// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import WormholySwift

@MainActor
final class WebSocketInterceptorTests: WebSocketTestCase {

    // MARK: - Tests

    func testWebSocketEnabledStateIsSharedWithObjectiveCBridge() {
        Wormholy.setWebSocketEnabled(true)
        XCTAssertTrue(WHWebSocketRecorder.isEnabled)

        Wormholy.setWebSocketEnabled(false)
        XCTAssertFalse(WHWebSocketRecorder.isEnabled)
    }

    func testDelegateProxyRequiresWebSocketTrackingWhenSessionIsCreated() {
        Wormholy.setWebSocketEnabled(false)
        let disabledDelegate = WebSocketLifecycleDelegate()
        let disabledSession = URLSession(configuration: .ephemeral,
                                         delegate: disabledDelegate,
                                         delegateQueue: nil)
        XCTAssertTrue(disabledSession.delegate === disabledDelegate)

        Wormholy.setWebSocketEnabled(true)
        let enabledDelegate = WebSocketLifecycleDelegate()
        let enabledSession = URLSession(configuration: .ephemeral,
                                        delegate: enabledDelegate,
                                        delegateQueue: nil)
        XCTAssertFalse(enabledSession.delegate === enabledDelegate)
    }

    func testDelegateProxyForwardsAndCapturesLifecycleEvents() async throws {
        Wormholy.setWebSocketEnabled(true)
        let delegateOpened = expectation(description: "original delegate received didOpen")
        let delegateClosed = expectation(description: "original delegate received didClose")
        let delegate = WebSocketLifecycleDelegate(onOpen: { delegateOpened.fulfill() },
                                                  onClose: { delegateClosed.fulfill() })
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        let model = try XCTUnwrap(task.wormholyModel)
        let proxy = try XCTUnwrap(session.delegate as? URLSessionWebSocketDelegate)
        let didOpen = try XCTUnwrap(proxy.urlSession(_:webSocketTask:didOpenWithProtocol:))
        let didClose = try XCTUnwrap(proxy.urlSession(_:webSocketTask:didCloseWith:reason:))

        let modelOpened = openedExpectation(in: model)
        didOpen(session, task, "chat")

        await fulfillment(of: [delegateOpened, modelOpened], timeout: 1)
        XCTAssertEqual(model.negotiatedProtocol, "chat")

        let modelClosed = closedExpectation(in: model)
        didClose(session, task, .normalClosure, Data("done".utf8))

        await fulfillment(of: [delegateClosed, modelClosed], timeout: 1)
        XCTAssertEqual(model.closeCode, .normalClosure)
        XCTAssertEqual(model.closeReason, "done")
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

    func testRecorderPublishesMessageBurstOnce() async throws {
        Wormholy.setWebSocketEnabled(true)
        Wormholy.webSocketMessageLimit = nil
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        let model = try XCTUnwrap(task.wormholyModel)
        let messagesRecorded = expectation(description: "messages recorded in one publication")
        var publicationCount = 0

        model.$messages
            .dropFirst()
            .sink { messages in
                publicationCount += 1
                if messages.map(\.text) == ["first", "second", "third"] {
                    messagesRecorded.fulfill()
                }
            }
            .store(in: &cancellables)

        WHWebSocketRecorder.recordSentText(task, text: "first")
        WHWebSocketRecorder.recordReceivedText(task, text: "second")
        WHWebSocketRecorder.recordSentText(task, text: "third")

        await fulfillment(of: [messagesRecorded], timeout: 1)
        XCTAssertEqual(publicationCount, 1)
    }

    func testRecorderAppliesPendingMessageLimitPerTask() async throws {
        Wormholy.setWebSocketEnabled(true)
        Wormholy.webSocketMessageLimit = 10
        let firstTaskURL = URL(string: "wss://example.com/first/\(UUID().uuidString)")!
        let secondTaskURL = URL(string: "wss://example.com/second/\(UUID().uuidString)")!
        let firstTask = URLSession.shared.webSocketTask(with: firstTaskURL)
        let secondTask = URLSession.shared.webSocketTask(with: secondTaskURL)
        let firstModel = try XCTUnwrap(firstTask.wormholyModel)
        let secondModel = try XCTUnwrap(secondTask.wormholyModel)
        let firstMessagesRecorded = expectation(description: "first task messages recorded")
        let secondMessagesRecorded = expectation(description: "second task messages recorded")
        let expectedFirstMessages = (90..<100).map { "first-\($0)" }
        let expectedSecondMessages = (90..<100).map { "second-\($0)" }

        firstModel.$messages
            .dropFirst()
            .filter { $0.map(\.text) == expectedFirstMessages }
            .prefix(1)
            .sink { _ in firstMessagesRecorded.fulfill() }
            .store(in: &cancellables)

        secondModel.$messages
            .dropFirst()
            .filter { $0.map(\.text) == expectedSecondMessages }
            .prefix(1)
            .sink { _ in secondMessagesRecorded.fulfill() }
            .store(in: &cancellables)

        for index in 0..<100 {
            WHWebSocketRecorder.recordSentText(firstTask, text: "first-\(index)")
            WHWebSocketRecorder.recordReceivedText(secondTask, text: "second-\(index)")
        }

        await fulfillment(of: [firstMessagesRecorded, secondMessagesRecorded], timeout: 1)
        XCTAssertEqual(firstModel.messages.map(\.text), expectedFirstMessages)
        XCTAssertEqual(secondModel.messages.map(\.text), expectedSecondMessages)
    }

    func testRecorderFlushesMessagesBeforeLifecycleEvent() async throws {
        Wormholy.setWebSocketEnabled(true)
        let task = URLSession.shared.webSocketTask(with: URL(string: "wss://example.com/socket/\(UUID().uuidString)")!)
        let model = try XCTUnwrap(task.wormholyModel)
        let connectionClosed = expectation(description: "connection closed after messages are recorded")

        model.$closedAt
            .dropFirst()
            .sink { _ in
                XCTAssertEqual(model.messages.map(\.text), ["before close"])
                connectionClosed.fulfill()
            }
            .store(in: &cancellables)

        WHWebSocketRecorder.recordSentText(task, text: "before close")
        WHWebSocketRecorder.recordClosed(task, closeCode: .normalClosure, reason: nil)

        await fulfillment(of: [connectionClosed], timeout: 1)
    }

    func testDisabledInterceptorDoesNotAttachModel() {
        Wormholy.setWebSocketEnabled(false)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        XCTAssertNil(task.wormholyModel)
    }

    func testEnablingTrackingDoesNotAttachPreviouslyCreatedTask() {
        Wormholy.setWebSocketEnabled(false)

        let url = URL(string: "wss://example.com/socket/\(UUID().uuidString)")!
        let task = URLSession.shared.webSocketTask(with: url)

        Wormholy.setWebSocketEnabled(true)

        XCTAssertNil(task.wormholyModel)
        XCTAssertTrue(Storage.shared.webSocketConnections.isEmpty)
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
