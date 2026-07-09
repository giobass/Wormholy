import XCTest
@testable import WormholySwift

final class WebSocketModelTests: XCTestCase {
    @MainActor
    override func tearDown() async throws {
        Storage.webSocketMessageLimit = nil
        try await super.tearDown()
    }

    @MainActor
    func testInitialStateIsConnecting() {
        let model = WebSocketModel(url: "wss://example.com/socket")
        XCTAssertEqual(model.state, .connecting)
        XCTAssertNil(model.openedAt)
        XCTAssertTrue(model.messages.isEmpty)
    }

    @MainActor
    func testMarkOpenedRecordsNegotiatedProtocol() async {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.markOpened(protocol: "chat")
        await waitForMainQueue()

        XCTAssertEqual(model.state, .open)
        XCTAssertNotNil(model.openedAt)
        XCTAssertEqual(model.negotiatedProtocol, "chat")
    }

    @MainActor
    func testAddMessageAppendsWithoutMarkingOpen() async {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("hello"))
        await waitForMainQueue()

        XCTAssertEqual(model.state, .connecting)
        XCTAssertNil(model.openedAt)
        XCTAssertEqual(model.messages.count, 1)
        XCTAssertEqual(model.messages.first?.direction, .sent)
        XCTAssertEqual(model.messages.first?.text, "hello")

        model.addMessage(direction: .received, message: .data("world".data(using: .utf8)!))
        await waitForMainQueue()

        XCTAssertEqual(model.messages.count, 2)
        XCTAssertEqual(model.messages.last?.direction, .received)
        XCTAssertEqual(model.messages.last?.text, "world")
    }

    @MainActor
    func testAddMessageRespectsWebSocketMessageLimit() async {
        Storage.webSocketMessageLimit = 2
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("first"))
        model.addMessage(direction: .received, message: .string("second"))
        model.addMessage(direction: .sent, message: .string("third"))
        await waitForMainQueue()

        XCTAssertEqual(model.messages.map(\.text), ["second", "third"])
    }

    @MainActor
    func testNilWebSocketMessageLimitKeepsCompleteHistory() async {
        Storage.webSocketMessageLimit = nil
        let model = WebSocketModel(url: "wss://example.com/socket")

        for index in 0..<3 {
            model.addMessage(direction: .sent, message: .string("\(index)"))
        }
        await waitForMainQueue()

        XCTAssertEqual(model.messages.map(\.text), ["0", "1", "2"])
    }

    @MainActor
    func testMarkClosedRecordsCodeAndReason() async {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markOpened()

        model.markClosed(code: .normalClosure, reason: "bye".data(using: .utf8))
        await waitForMainQueue()

        XCTAssertEqual(model.state, .closed)
        XCTAssertEqual(model.closeCode, .normalClosure)
        XCTAssertEqual(model.closeReason, "bye")
        XCTAssertNotNil(model.closedAt)
    }

    @MainActor
    func testMarkErrorSetsFailedState() async {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markError(URLError(.notConnectedToInternet))
        await waitForMainQueue()

        XCTAssertEqual(model.state, .failed)
        XCTAssertNotNil(model.errorDescription)
    }

    @MainActor
    func testErrorAfterCloseDoesNotOverrideClosedState() async {
        let model = WebSocketModel(url: "wss://example.com/socket")
        model.markClosed(code: .normalClosure, reason: "done".data(using: .utf8))
        await waitForMainQueue()

        model.markError(URLError(.networkConnectionLost))
        await waitForMainQueue()

        XCTAssertEqual(model.state, .closed)
        XCTAssertNil(model.errorDescription)
    }

    @MainActor
    func testRefineConnectionMetadataUpgradesNormalizedSchemeToWebSocket() async {
        // URLSession's `webSocketTask(with: URL)` delegates internally to `webSocketTask(with:
        // URLRequest)`, which normalizes ws/wss to http/https. This is what corrects it back.
        let model = WebSocketModel(url: "https://example.com/socket", host: "example.com", scheme: "https")
        let wssURL = URL(string: "wss://example.com/socket")!

        model.refineConnectionMetadataIfNeeded(url: wssURL, headers: [:], protocols: [])
        await waitForMainQueue()

        XCTAssertEqual(model.url, wssURL.absoluteString)
        XCTAssertEqual(model.scheme, "wss")
    }

    @MainActor
    func testRefineConnectionMetadataDoesNotDowngradeWebSocketScheme() async {
        let model = WebSocketModel(url: "wss://example.com/socket", host: "example.com", scheme: "wss")

        model.refineConnectionMetadataIfNeeded(url: URL(string: "https://example.com/socket")!, headers: [:], protocols: [])
        await waitForMainQueue()

        XCTAssertEqual(model.scheme, "wss")
    }

    @MainActor
    func testRefineConnectionMetadataFillsInMissingProtocolsAndHeaders() async {
        let model = WebSocketModel(url: "https://example.com/socket", host: "example.com", scheme: "https")

        model.refineConnectionMetadataIfNeeded(url: URL(string: "wss://example.com/socket")!,
                                                headers: ["Authorization": "Bearer token"],
                                                protocols: ["chat"])
        await waitForMainQueue()

        XCTAssertEqual(model.requestHeaders["Authorization"], "Bearer token")
        XCTAssertEqual(model.requestedProtocols, ["chat"])
    }

    @MainActor
    func testUpdateResponseHeadersStoresHandshakeHeaders() async {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.updateResponseHeaders(["Upgrade": "websocket"])
        await waitForMainQueue()

        XCTAssertEqual(model.responseHeaders["Upgrade"], "websocket")
    }

    @MainActor
    func testWebSocketExportIncludesHeadersAndMessages() async {
        let model = WebSocketModel(url: "wss://example.com/socket",
                                   requestHeaders: ["Authorization": "Bearer token"],
                                   responseHeaders: ["Upgrade": "websocket"])

        model.addMessage(direction: .sent, message: .string("{\"type\":\"ping\"}"))
        model.addMessage(direction: .received, message: .string("{\"type\":\"pong\"}"))
        await waitForMainQueue()

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

    @MainActor
    func testWebSocketBodyTextPreservesPlainTextMessages() async {
        let model = WebSocketModel(url: "wss://example.com/socket")

        model.addMessage(direction: .sent, message: .string("plain text message"))
        await waitForMainQueue()

        XCTAssertEqual(model.messages.first.map(WebSocketModelBeautifier.bodyText), "plain text message")
    }
}
