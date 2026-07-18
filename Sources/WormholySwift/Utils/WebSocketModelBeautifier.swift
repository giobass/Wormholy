// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

@MainActor
internal enum WebSocketModelBeautifier {
    private static let previewLimit = 160

    static func overview(connection: WebSocketModel) -> (LocalizedStringKey, String) {
        var lines = [
            "**URL:** \(connection.url)",
            "**Method:** GET",
            "**State:** \(connection.state.title)",
            "**Start Time:** \(formatDate(connection.startDate))",
            "**Opened Time:** \(formatDate(connection.openedAt))",
            "**Closed Time:** \(formatDate(connection.closedAt))",
            "**Duration:** \(duration(connection))",
            "**Sent Messages:** \(connection.messages.filter { $0.direction == .sent }.count)",
            "**Received Messages:** \(connection.messages.filter { $0.direction == .received }.count)",
            "**Total Messages:** \(connection.messages.count)"
        ]

        if !connection.requestedProtocols.isEmpty {
            lines.append("**Requested Protocols:** \(connection.requestedProtocols.joined(separator: ", "))")
        }
        if let negotiatedProtocol = connection.negotiatedProtocol {
            lines.append("**Negotiated Protocol:** \(negotiatedProtocol)")
        }
        if let closeCode = connection.closeCode {
            lines.append("**Close Code:** \(closeCode.rawValue)")
        }
        if let closeReason = connection.closeReason {
            lines.append("**Close Reason:** \(closeReason)")
        }

        let combinedString = lines.joined(separator: "\n")
        return (LocalizedStringKey(combinedString), combinedString)
    }

    static func header(_ headers: [String: String]) -> (LocalizedStringKey, String) {
        guard !headers.isEmpty else {
            return (LocalizedStringKey("-"), "-")
        }

        let combinedString = headers
            .sorted { $0.key < $1.key }
            .map { "**\($0.key):** \($0.value)" }
            .joined(separator: "\n")
        return (LocalizedStringKey(combinedString), combinedString)
    }

    static func messagePreview(_ message: WebSocketMessage) -> String {
        let body = bodyText(message)
        if body.count <= previewLimit { return body }
        let endIndex = body.index(body.startIndex, offsetBy: previewLimit)
        return String(body[..<endIndex]) + "..."
    }

    static func bodyText(_ message: WebSocketMessage) -> String {
        if let text = message.text {
            return text.prettyPrintedJSON ?? text
        }
        return "<binary \(message.byteCount) bytes>"
    }

    static func messageMetadata(_ message: WebSocketMessage) -> String {
        "\(formatTime(message.occurredAt)) - \(messageKind(message)) - \(message.byteCount) B"
    }

    static func txtExport(connection: WebSocketModel) -> String {
        var text = ""
        text += "*** Overview *** \n"
        text += "\(overview(connection: connection).1)\n\n"
        text += "*** Request Header *** \n"
        text += "\(header(connection.requestHeaders).1)\n\n"
        text += "*** Response Header *** \n"
        text += "\(header(connection.responseHeaders).1)\n\n"

        text += "*** Messages *** \n"
        if connection.messages.isEmpty {
            text += "No messages captured.\n"
        } else {
            for message in connection.messages {
                text += "[\(formatDate(message.occurredAt))] \(message.direction.title) "
                text += "\(messageKind(message)) \(message.byteCount) B\n"
                text += "\(bodyText(message))\n\n"
            }
        }

        text += "------------------------------------------------------------------------\n"
        text += "------------------------------------------------------------------------\n"
        text += "------------------------------------------------------------------------\n\n\n\n"
        return text
    }

    private static func messageKind(_ message: WebSocketMessage) -> String {
        switch message.message {
        case .string: return "text"
        case .data: return "data"
        @unknown default: return "unknown"
        }
    }

    private static func duration(_ connection: WebSocketModel) -> String {
        let endDate = connection.closedAt ?? connection.failedAt ?? Date()
        guard endDate >= connection.startDate else { return "-" }
        return (endDate.timeIntervalSince(connection.startDate) * 1000).formattedMilliseconds()
    }

    private static func formatDate(_ date: Date?) -> String {
        date?.stringWithFormat(dateFormat: "MMM d yyyy - HH:mm:ss.SSS") ?? "-"
    }

    private static func formatTime(_ date: Date) -> String {
        date.stringWithFormat(dateFormat: "HH:mm:ss.SSS") ?? "-"
    }
}
