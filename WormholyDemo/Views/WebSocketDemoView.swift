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
                        .disabled(viewModel.isConnected)

                    Toggle("Test headers", isOn: $viewModel.includesTestHeaders)
                        .onChange(of: viewModel.includesTestHeaders) { _ in
                            viewModel.logTestHeadersState()
                        }
                        .disabled(viewModel.isConnected)

                    if viewModel.isConnected {
                        Button(role: .destructive) {
                            focusedField = nil
                            viewModel.close()
                        } label: {
                            WebSocketActionLabel("Disconnect", systemImage: "xmark.circle", role: .destructive)
                        }
                    } else {
                        Button {
                            focusedField = nil
                            viewModel.connect()
                        } label: {
                            WebSocketActionLabel("Connect", systemImage: "bolt.horizontal")
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

                    Button {
                        sendMessage()
                    } label: {
                        WebSocketActionLabel("Send message", systemImage: "paperplane")
                    }
                    .disabled(!viewModel.canSendMessage)

                    Button {
                        viewModel.sendSampleJSON()
                    } label: {
                        WebSocketActionLabel("Send sample JSON", systemImage: "curlybraces")
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

private struct WebSocketActionLabel: View {
    // MARK: - Properties

    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let systemImage: String
    let role: ButtonRole?

    init(_ title: String, systemImage: String, role: ButtonRole? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
    }

    // MARK: - Body

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(foregroundStyle)
            .opacity(isEnabled ? 1 : 0.55)
    }

    // MARK: - Style

    private var foregroundStyle: Color {
        if !isEnabled {
            return .secondary
        } else if role == .destructive {
            return .red
        } else {
            return .accentColor
        }
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
