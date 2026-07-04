//
//  WebSocketDemoViewModel.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import Foundation

@MainActor
final class WebSocketDemoViewModel: ObservableObject {
    // MARK: - Properties

    @Published var urlText = "wss://ws.postman-echo.com/raw"
    @Published var messageText = ""
    @Published var includesTestHeaders = true
    @Published private(set) var isConnected = false
    @Published private(set) var logEntries: [String] = []

    private let client: WebSocketEchoClient
    private let logLimit = 40
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Status

    var canSendMessage: Bool {
        isConnected && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canConnect: Bool {
        !isConnected && hasValidURL
    }

    var connectionStatusText: String {
        if isConnected {
            return "Connected. Disconnect to change the URL or headers."
        } else if !hasValidURL {
            return "Enter a valid WebSocket URL to connect."
        } else {
            return "Disconnected."
        }
    }

    var messageStatusText: String {
        if !isConnected {
            return "Connect to the WebSocket before sending messages."
        } else if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a message to enable Send message."
        } else {
            return "Ready to send."
        }
    }

    private var hasValidURL: Bool {
        URL(string: urlText) != nil
    }

    // MARK: - Init

    init(client: WebSocketEchoClient = .sharedInstance) {
        self.client = client
        configureClientCallbacks()
    }

    // MARK: - Connection Actions

    func connect() {
        guard let url = URL(string: urlText) else {
            appendLog("Error: invalid WebSocket URL")
            return
        }

        appendLog("Opening: \(url.absoluteString)")
        logTestHeadersState()
        client.connect(to: url, includesTestHeaders: includesTestHeaders)
    }

    // MARK: - Message Actions

    func sendMessage() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        client.send(message)
        messageText = ""
    }

    func sendSampleJSON() {
        let formatter = ISO8601DateFormatter()
        let message = """
        {"type":"wormholy.demo","sentAt":"\(formatter.string(from: Date()))","payload":{"message":"Hello from Wormholy","sequence":\(logEntries.count + 1)}}
        """
        client.send(message)
    }

    func close() {
        client.close()
    }

    func logTestHeadersState() {
        appendLog("Test headers: \(includesTestHeaders ? "enabled" : "disabled")")
    }

    // MARK: - Client Callbacks

    private func configureClientCallbacks() {
        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.appendLog(event.text)
            }
        }

        client.onConnectionStateChanged = { [weak self] isConnected in
            Task { @MainActor in
                self?.isConnected = isConnected
            }
        }
    }

    // MARK: - Log

    private func appendLog(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        logEntries.append("[\(timestamp)] \(message)")

        if logEntries.count > logLimit {
            logEntries = Array(logEntries.suffix(logLimit))
        }
    }
}
