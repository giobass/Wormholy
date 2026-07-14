// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import WormholySwift

@MainActor
final class WebSocketModelTests: XCTestCase {
    override func tearDown() async throws {
        Wormholy.webSocketMessageLimit = nil
        try await super.tearDown()
    }

    func testInitialStateIsConnecting() {
        let model = WebSocketModel(url: "wss://example.com/socket")
        XCTAssertEqual(model.state, .connecting)
        XCTAssertNil(model.openedAt)
        XCTAssertTrue(model.messages.isEmpty)
    }

    func testMarkOpenedRecordsNegotiatedProtocol() {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.markOpened(protocol: "chat")

        XCTAssertEqual(model.state, .open)
        XCTAssertNotNil(model.openedAt)
        XCTAssertEqual(model.negotiatedProtocol, "chat")
    }

    func testAddMessageAppendsWithoutMarkingOpen() {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("hello"))

        XCTAssertEqual(model.state, .connecting)
        XCTAssertNil(model.openedAt)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages.first?.direction, .sent)
        XCTAssertEqual(model.messages.first?.text, "hello")

        model.addMessage(direction: .received, message: .data("world".data(using: .utf8)!))

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.direction, .received)
        XCTAssertEqual(model.messages.last?.text, "world")
    }

    func testPublicWebSocketMessageLimitIsAppliedImmediately() {
        Wormholy.webSocketMessageLimit = 2
        XCTAssertEqual(Wormholy.webSocketMessageLimit?.intValue, 2)

        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("first"))
        model.addMessage(direction: .received, message: .string("second"))
        model.addMessage(direction: .sent, message: .string("third"))

        XCTAssertEqual(model.messages.map(\.text), ["second", "third"])
    }

    func testNilWebSocketMessageLimitKeepsCompleteHistory() {
        Wormholy.webSocketMessageLimit = nil
        XCTAssertNil(Wormholy.webSocketMessageLimit)
        let model = WebSocketModel(url: "wss://example.com/socket")

        for index in 0..<3 {
            model.addMessage(direction: .sent, message: .string("\(index)"))
        }

        XCTAssertEqual(model.messages.map(\.text), ["0", "1", "2"])
    }

    func testMarkClosedRecordsCodeAndReason() {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markOpened()

        model.markClosed(code: .normalClosure, reason: "bye".data(using: .utf8))

        XCTAssertEqual(model.state, .closed)
        XCTAssertEqual(model.closeCode, .normalClosure)
        XCTAssertEqual(model.closeReason, "bye")
        XCTAssertNotNil(model.closedAt)
    }

    func testMarkErrorSetsFailedState() {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markError(URLError(.notConnectedToInternet))

        XCTAssertEqual(model.state, .failed)
        XCTAssertNotNil(model.errorDescription)
    }

    func testErrorAfterCloseDoesNotOverrideClosedState() {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markClosed(code: .normalClosure, reason: "done".data(using: .utf8))

        model.markError(URLError(.networkConnectionLost))

        XCTAssertEqual(model.state, .closed)
        XCTAssertNil(model.errorDescription)
    }

    func testRefineConnectionMetadataUpgradesNormalizedSchemeToWebSocket() {
        // URLSession's `webSocketTask(with: URL)` delegates internally to `webSocketTask(with:
        // URLRequest)`, which normalizes ws/wss to http/https. This is what corrects it back.
        let model = WebSocketModel(url: "https://example.com/socket", host: "example.com", scheme: "https")
        let wssURL = URL(string: "wss://example.com/socket")!

        model.refineConnectionMetadataIfNeeded(url: wssURL, headers: [:], protocols: [])

        XCTAssertEqual(model.url, wssURL.absoluteString)
        XCTAssertEqual(model.scheme, "wss")
    }

    func testRefineConnectionMetadataDoesNotDowngradeWebSocketScheme() {
        let model = WebSocketModel(url: "wss://example.com/socket", host: "example.com", scheme: "wss")

        model.refineConnectionMetadataIfNeeded(url: URL(string: "https://example.com/socket")!, headers: [:], protocols: [])

        XCTAssertEqual(model.scheme, "wss")
    }

    func testRefineConnectionMetadataFillsInMissingProtocolsAndHeaders() {
        let model = WebSocketModel(url: "https://example.com/socket", host: "example.com", scheme: "https")

        model.refineConnectionMetadataIfNeeded(url: URL(string: "wss://example.com/socket")!,
                                                headers: ["Authorization": "Bearer token"],
                                                protocols: ["chat"])

        XCTAssertEqual(model.requestHeaders["Authorization"], "Bearer token")
        XCTAssertEqual(model.requestedProtocols, ["chat"])
    }

    func testUpdateResponseHeadersStoresHandshakeHeaders() {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.updateResponseHeaders(["Upgrade": "websocket"])

        XCTAssertEqual(model.responseHeaders["Upgrade"], "websocket")
    }

    func testWebSocketExportIncludesHeadersAndMessages() {
        let model = WebSocketModel(url: "wss://example.com/socket",
                                   requestHeaders: ["Authorization": "Bearer token"],
                                   responseHeaders: ["Upgrade": "websocket"])

        model.addMessage(direction: .sent, message: .string("{\"type\":\"ping\"}"))
        model.addMessage(direction: .received, message: .string("{\"type\":\"pong\"}"))

        let export = WebSocketModelBeautifier.txtExport(connection: model)

        XCTAssertTrue(export.contains("*** Overview ***"))
        XCTAssertTrue(export.contains("*** Request Header ***"))
        XCTAssertTrue(export.contains("Authorization"))
        XCTAssertTrue(export.contains("*** Response Header ***"))
        XCTAssertTrue(export.contains("Upgrade"))
        XCTAssertTrue(export.contains("*** Messages ***"))
        XCTAssertTrue(export.contains("Sent text"))
        XCTAssertTrue(export.contains("Received text"))
    }

    func testWebSocketBodyTextPreservesPlainTextMessages() {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("plain text message"))

        XCTAssertEqual(model.messages.first.map(WebSocketModelBeautifier.bodyText), "plain text message")
    }
}
