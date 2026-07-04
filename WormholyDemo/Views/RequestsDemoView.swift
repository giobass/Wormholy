//
//  RequestsDemoView.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import SwiftUI

struct RequestsDemoView: View {
    // MARK: - Properties

    @StateObject private var viewModel = RequestsDemoViewModel()

    private let automaticRequestTimer = Timer
        .publish(every: RequestsDemoViewModel.automaticHTTPInterval, on: .main, in: .common)
        .autoconnect()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Automatic traffic", isOn: $viewModel.isAutomaticHTTPRunning)
                        .onChange(of: viewModel.isAutomaticHTTPRunning) { _ in
                            viewModel.logAutomaticHTTPState()
                        }

                    DemoActionButton("Get post", systemImage: "doc.text") {
                        viewModel.getPost()
                    }

                    DemoActionButton("New random post", systemImage: "plus.circle") {
                        viewModel.newRandomPost()
                    }

                    DemoActionButton("Wrong URL", systemImage: "exclamationmark.triangle") {
                        viewModel.getWrongURL()
                    }

                    DemoActionButton("Get photos", systemImage: "photo.on.rectangle") {
                        viewModel.getPhotos()
                    }
                } footer: {
                    Text(viewModel.automaticHTTPStatus)
                }
            }
            .navigationTitle("HTTP Requests")
            .inspectorToolbar()
            .onReceive(automaticRequestTimer) { _ in
                viewModel.generateAutomaticTrafficIfNeeded()
            }
        }
    }
}

#Preview {
    RequestsDemoView()
}
