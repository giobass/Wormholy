//
//  WebSocketModel.swift
//  Wormholy
//
//  Created by Giovanni Bassolino on 03/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//
import Foundation
import SwiftUI

internal enum WebSocketMessageDirection: Equatable {
    case sent
    case received

    internal var title: String {
        switch self {
        case .sent: return "Sent"
        case .received: return "Received"
        }
    }

    internal var color: Color {
        switch self {
        case .sent: return .blue
        case .received: return .green
        }
    }
}

internal struct WebSocketMessage: Identifiable {
    internal let id: String = UUID().uuidString
    internal let direction: WebSocketMessageDirection
    internal let timestamp: Date
    internal let message: URLSessionWebSocketTask.Message

    internal var text: String? {
        switch message {
        case .string(let string): return string
        case .data(let data): return String(data: data, encoding: .utf8)
        @unknown default: return nil
        }
    }

    internal var data: Data? {
        switch message {
        case .data(let data): return data
        case .string(let string): return string.data(using: .utf8)
        @unknown default: return nil
        }
    }

    internal var byteCount: Int {
        switch message {
        case .string(let string): return string.utf8.count
        case .data(let data): return data.count
        @unknown default: return 0
        }
    }
}

internal enum WebSocketConnectionState: Equatable {
    case connecting
    case open
    case closed
    case failed

    internal var title: String {
        switch self {
        case .connecting: return "Connecting"
        case .open: return "Open"
        case .closed: return "Closed"
        case .failed: return "Failed"
        }
    }
}

internal class WebSocketModel: Identifiable, ObservableObject, Equatable {
    internal let id: String
    internal private(set) var url: String
    internal private(set) var host: String?
    internal private(set) var scheme: String?
    internal private(set) var requestHeaders: [String: String]
    internal private(set) var responseHeaders: [String: String]
    internal private(set) var requestedProtocols: [String]
    internal let startDate: Date

    @Published internal private(set) var messages: [WebSocketMessage] = []
    @Published internal private(set) var openedAt: Date?
    @Published internal private(set) var negotiatedProtocol: String?
    @Published internal private(set) var closedAt: Date?
    @Published internal private(set) var closeCode: URLSessionWebSocketTask.CloseCode?
    @Published internal private(set) var closeReason: String?
    @Published internal private(set) var errorDescription: String?

    internal var state: WebSocketConnectionState {
        if closedAt != nil { return .closed }
        if errorDescription != nil { return .failed }
        if openedAt != nil { return .open }
        return .connecting
    }

    internal init(id: String = UUID().uuidString,
                  url: String,
                  host: String? = nil,
                  scheme: String? = nil,
                  requestHeaders: [String: String] = [:],
                  responseHeaders: [String: String] = [:],
                  requestedProtocols: [String] = [],
                  startDate: Date = Date()) {
        self.id = id
        self.url = url
        self.host = host
        self.scheme = scheme
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.requestedProtocols = requestedProtocols
        self.startDate = startDate
    }

    /// `URLSession`'s WebSocket factory overloads are implemented internally in terms of
    /// one another (e.g. the `URL`-based one delegates to the `URLRequest`-based one, which
    /// normalizes the `ws`/`wss` scheme to `http`/`https`). Since all factory overloads are
    /// swizzled, the same task can get attached more than once; this refines the already
    /// -attached model instead of creating a second, orphaned one.
    internal func refineConnectionMetadataIfNeeded(url candidate: URL, headers: [String: String], protocols: [String]) {
        let candidateIsWebSocketScheme = ["ws", "wss"].contains(candidate.scheme?.lowercased() ?? "")
        let currentIsWebSocketScheme = ["ws", "wss"].contains(scheme?.lowercased() ?? "")
        if candidateIsWebSocketScheme && !currentIsWebSocketScheme {
            url = candidate.absoluteString
            host = candidate.host
            scheme = candidate.scheme
        }
        if requestHeaders.isEmpty && !headers.isEmpty {
            requestHeaders = headers
        }
        if requestedProtocols.isEmpty && !protocols.isEmpty {
            requestedProtocols = protocols
        }
    }

    internal func markOpened(protocol negotiatedProtocol: String? = nil) {
        DispatchQueue.main.async {
            if self.openedAt == nil {
                self.openedAt = Date()
            }
            if let negotiatedProtocol = negotiatedProtocol {
                self.negotiatedProtocol = negotiatedProtocol
            }
        }
    }

    internal func addMessage(direction: WebSocketMessageDirection, message: URLSessionWebSocketTask.Message) {
        DispatchQueue.main.async {
            self.messages.append(WebSocketMessage(direction: direction, timestamp: Date(), message: message))
        }
    }

    internal func updateResponseHeaders(_ headers: [String: String]) {
        DispatchQueue.main.async {
            guard !headers.isEmpty else { return }
            self.responseHeaders = headers
        }
    }

    internal func markClosed(code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            self.closedAt = Date()
            self.closeCode = code
            if let reason = reason {
                self.closeReason = String(data: reason, encoding: .utf8)
            }
        }
    }

    internal func markError(_ error: Error) {
        DispatchQueue.main.async {
            guard self.closedAt == nil else { return }
            self.errorDescription = error.localizedDescription
        }
    }

    internal static func == (lhs: WebSocketModel, rhs: WebSocketModel) -> Bool {
        return lhs.id == rhs.id
    }
}
