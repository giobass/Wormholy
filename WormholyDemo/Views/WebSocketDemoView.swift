//
//  WebSocketDemoView.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import SwiftUI

struct WebSocketDemoView: View {
    // MARK: - Properties

    @StateObject private var viewModel = WebSocketDemoViewModel()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case url
        case message
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("WebSocket URL", text: $viewModel.urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .focused($focusedField, equals: .url)
                        .onSubmit {
                            viewModel.connect()
                        }
                        .disabled(viewModel.isConnected || viewModel.isConnecting)

                    Toggle("Test headers", isOn: $viewModel.includesTestHeaders)
                        .onChange(of: viewModel.includesTestHeaders) { _ in
                            viewModel.logTestHeadersState()
                        }
                        .disabled(viewModel.isConnected || viewModel.isConnecting)

                    if viewModel.isConnected {
                        DemoActionButton(
                            "Disconnect",
                            systemImage: "xmark.circle",
                            tint: .red,
                            role: .destructive
                        ) {
                            focusedField = nil
                            viewModel.close()
                        }
                    } else {
                        DemoActionButton(
                            viewModel.isConnecting ? "Connecting" : "Connect",
                            systemImage: "bolt.horizontal",
                            isLoading: viewModel.isConnecting
                        ) {
                            focusedField = nil
                            viewModel.connect()
                        }
                        .disabled(!viewModel.canConnect)
                    }
                } footer: {
                    Text(viewModel.connectionStatusText)
                }

                Section {
                    TextField("Message", text: $viewModel.messageText)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .message)
                        .onSubmit {
                            sendMessage()
                        }
                        .disabled(!viewModel.isConnected)

                    DemoActionButton("Send message", systemImage: "paperplane") {
                        sendMessage()
                    }
                    .disabled(!viewModel.canSendMessage)

                    DemoActionButton("Send sample JSON", systemImage: "curlybraces") {
                        viewModel.sendSampleJSON()
                    }
                    .disabled(!viewModel.isConnected)
                } footer: {
                    Text(viewModel.messageStatusText)
                }

                Section {
                    WebSocketLogView(entries: viewModel.logEntries)
                }
            }
            .navigationTitle("WebSocket")
            .inspectorToolbar()
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        focusedField = nil
        viewModel.sendMessage()
    }
}

private struct WebSocketLogView: View {
    // MARK: - Properties

    let entries: [String]

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .id("log-bottom")
            }
            .frame(minHeight: 160)
            .onChange(of: entries) { _ in
                proxy.scrollTo("log-bottom", anchor: .bottom)
            }
        }
        .accessibilityLabel("WebSocket console log")
    }

    // MARK: - Text

    private var logText: String {
        entries.isEmpty ? "WebSocket console log" : entries.joined(separator: "\n")
    }
}

#Preview {
    WebSocketDemoView()
}
