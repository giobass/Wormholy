// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import XCTest
import Combine
@testable import WormholySwift

@MainActor
final class WebSocketRealTaskTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() async throws {
        cancellables.removeAll()
        Wormholy.setWebSocketEnabled(false)
        Wormholy.ignoredHosts = []
        Storage.shared.clearWebSocketConnections()
        try await super.tearDown()
    }

    func testRealTaskSendCapturesCompletionHandlerAndAsyncMessages() async throws {
        Wormholy.setWebSocketEnabled(true)
        let completionPayload = "completion-send-\(UUID().uuidString)"
        let asyncPayload = "async-send-\(UUID().uuidString)"

        let task = URLSession.shared.webSocketTask(with: Self.remoteEchoURL())
        addTeardownBlock { task.cancel(with: .goingAway, reason: nil) }
        task.resume()
        let model = try XCTUnwrap(task.wormholyModel)

        let sendCompletion = expectation(description: "completion send finished")
        task.send(.string(completionPayload)) { error in
            XCTAssertNil(error)
            sendCompletion.fulfill()
        }
        await fulfillment(of: [sendCompletion], timeout: 10)

        try await task.send(.string(asyncPayload))

        await fulfillment(of: [
            messageRecordedExpectation(in: model, direction: .sent, text: completionPayload),
            messageRecordedExpectation(in: model, direction: .sent, text: asyncPayload)
        ], timeout: 5)
    }

    func testRealTaskReceiveCapturesCompletionHandlerAndAsyncMessages() async throws {
        Wormholy.setWebSocketEnabled(true)
        let completionPayload = "completion-receive-\(UUID().uuidString)"
        let asyncPayload = "async-receive-\(UUID().uuidString)"

        let task = URLSession.shared.webSocketTask(with: Self.remoteEchoURL())
        addTeardownBlock { task.cancel(with: .goingAway, reason: nil) }
        task.resume()
        let model = try XCTUnwrap(task.wormholyModel)

        try await task.send(.string(completionPayload))

        let receiveCompletion = expectation(description: "completion receive finished")
        task.receive { result in
            switch result {
            case .success(.string(let text)):
                XCTAssertEqual(text, completionPayload)
            case .success:
                XCTFail("Expected a text WebSocket message.")
            case .failure(let error):
                XCTFail("Expected a received message, got error: \(error)")
            }
            receiveCompletion.fulfill()
        }
        await fulfillment(of: [receiveCompletion], timeout: 5)

        try await task.send(.string(asyncPayload))
        let asyncMessage = try await task.receive()
        guard case .string(let asyncText) = asyncMessage else {
            return XCTFail("Expected a text WebSocket message.")
        }
        XCTAssertEqual(asyncText, asyncPayload)

        await fulfillment(of: [
            messageRecordedExpectation(in: model, direction: .received, text: completionPayload),
            messageRecordedExpectation(in: model, direction: .received, text: asyncPayload)
        ], timeout: 5)
    }

    private static func remoteEchoURL() -> URL {
        URL(string: "wss://ws.postman-echo.com/raw")!
    }

    private func messageRecordedExpectation(in model: WebSocketModel,
                                            direction: WebSocketMessageDirection,
                                            text: String) -> XCTestExpectation {
        let expectation = expectation(description: "recorded \(direction.title) message")
        let matches: ([WebSocketMessage]) -> Bool = { messages in
            messages.contains { $0.direction == direction && $0.text == text }
        }

        if matches(model.messages) {
            expectation.fulfill()
        } else {
            model.$messages
                .filter(matches)
                .prefix(1)
                .sink { _ in expectation.fulfill() }
                .store(in: &cancellables)
        }
        return expectation
    }
}
