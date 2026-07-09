//
//  WebSocketEchoClient.swift
//  Wormholy-Demo-iOS
//
//  Created by Giovanni Bassolino on 03/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import Foundation

final class WebSocketEchoClient: NSObject {
    static let sharedInstance = WebSocketEchoClient()

    enum Event {
        case connected(URL)
        case sent(String)
        case received(String)
        case closed(URLSessionWebSocketTask.CloseCode, String?)
        case failed(String)

        var text: String {
            switch self {
            case .connected(let url):
                return "Connected: \(url.absoluteString)"
            case .sent(let message):
                return "Sent: \(message)"
            case .received(let message):
                return "Received: \(message)"
            case .closed(let code, let reason):
                return "Closed: \(code.rawValue)\(reason.map { " (\($0))" } ?? "")"
            case .failed(let message):
                return "Error: \(message)"
            }
        }
    }

    var onEvent: ((Event) -> Void)?
    var onConnectionStateChanged: ((Bool) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var isConnected = false {
        didSet {
            guard isConnected != oldValue else { return }
            DispatchQueue.main.async { [isConnected, onConnectionStateChanged] in
                onConnectionStateChanged?(isConnected)
            }
        }
    }

    func connect(to url: URL, includesTestHeaders: Bool) {
        close(code: .goingAway, reason: "Opening a new WebSocket")

        var request = URLRequest(url: url)
        if includesTestHeaders {
            request.setValue("WormholyDemo", forHTTPHeaderField: "X-Wormholy-Client")
            request.setValue("websocket-demo", forHTTPHeaderField: "X-Wormholy-Feature")
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task

        task.resume()
        listen()
    }

    func send(_ message: String) {
        guard let task else {
            emit(.failed("No active WebSocket"))
            return
        }

        task.send(.string(message)) { [weak self] error in
            if let error {
                self?.emit(.failed(error.localizedDescription))
            } else {
                self?.emit(.sent(message))
            }
        }
    }

    func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: String? = "Closed from demo") {
        guard task != nil || session != nil else { return }

        task?.cancel(with: code, reason: reason?.data(using: .utf8))
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        isConnected = false
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.emit(.received(text))
                case .data(let data):
                    self.emit(.received("<binary \(data.count) bytes>"))
                @unknown default:
                    break
                }
                self.listen()
            case .failure(let error):
                self.emit(.failed(error.localizedDescription))
                self.isConnected = false
            }
        }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [onEvent] in
            onEvent?(event)
        }
    }
}

extension WebSocketEchoClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        isConnected = true
        emit(.connected(webSocketTask.currentRequest?.url ?? webSocketTask.originalRequest?.url ?? URL(string: "wss://unknown")!))
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        isConnected = false
        emit(.closed(closeCode, reason.flatMap { String(data: $0, encoding: .utf8) }))
    }
}
