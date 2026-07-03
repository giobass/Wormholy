//
//  WebSocketDetailView.swift
//  Wormholy
//
//  Created by Giovanni Bassolino on 03/07/26.
//

import SwiftUI

internal struct WebSocketDetailView: View {
    @ObservedObject var connection: WebSocketModel
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShareSheetPresented = false

    var body: some View {
        List {
            Section("Overview") {
                Text(WebSocketModelBeautifier.overview(connection: connection).0)
                    .onTapGesture {
                        copyToClipboard(text: WebSocketModelBeautifier.overview(connection: connection).1)
                    }
            }

            if !connection.requestHeaders.isEmpty {
                Section("Request Header") {
                    Text(WebSocketModelBeautifier.header(connection.requestHeaders).0)
                        .onTapGesture {
                            copyToClipboard(text: WebSocketModelBeautifier.header(connection.requestHeaders).1)
                        }
                }
            }

            if !connection.responseHeaders.isEmpty {
                Section("Response Header") {
                    Text(WebSocketModelBeautifier.header(connection.responseHeaders).0)
                        .onTapGesture {
                            copyToClipboard(text: WebSocketModelBeautifier.header(connection.responseHeaders).1)
                        }
                }
            }

            if let errorDescription = connection.errorDescription {
                Section("Error") {
                    Text("**Error**: \(errorDescription)")
                        .foregroundColor(.red)
                        .onTapGesture { copyToClipboard(text: errorDescription) }
                }
            }

            Section("Messages (\(connection.messages.count))") {
                if connection.messages.isEmpty {
                    Text("No messages captured yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(connection.messages) { message in
                        WebSocketMessageRow(message: message)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .listStyle(.insetGrouped)
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShareSheetPresented = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ShareUtils.shareWebSocket(connection: connection)
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private var detailTitle: String {
        guard let url = URL(string: connection.url) else { return "WebSocket" }
        if let host = url.host, !host.isEmpty { return host }
        return "WebSocket"
    }

    private func copyToClipboard(text: String) {
        UIPasteboard.general.string = text
        alertMessage = "Copied to clipboard"
        showAlert = true
    }
}

private struct WebSocketMessageRow: View {
    let message: WebSocketMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.direction.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(message.direction.color)

                Text(WebSocketModelBeautifier.messageMetadata(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(WebSocketModelBeautifier.messagePreview(message))
                .font(.system(.footnote, design: .monospaced))
                .lineLimit(3)

            if let data = message.data {
                NavigationLink("View body") {
                    BodyDetailView(dataBody: data, kind: .webSocketMessage)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WebSocketDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let connection = WebSocketModel(
            url: "wss://ws.postman-echo.com/raw",
            requestHeaders: [
                "X-Wormholy-Client": "WormholyDemo",
                "X-Wormholy-Feature": "websocket-demo"
            ],
            responseHeaders: ["Upgrade": "websocket"],
            requestedProtocols: ["chat"]
        )
        connection.markOpened()
        connection.addMessage(direction: .sent, message: .string("{\"type\":\"subscribe\"}"))
        connection.addMessage(direction: .received, message: .string("{\"type\":\"ack\"}"))
        connection.addMessage(direction: .received, message: .data("binary-payload".data(using: .utf8)!))

        let closedConnection = WebSocketModel(url: "wss://ws.postman-echo.com/raw")
        closedConnection.markOpened()
        closedConnection.addMessage(direction: .sent, message: .string("ping"))
        closedConnection.markClosed(code: .normalClosure, reason: "done".data(using: .utf8))

        return Group {
            NavigationStack { WebSocketDetailView(connection: connection) }
            NavigationStack { WebSocketDetailView(connection: closedConnection) }
        }
    }
}
