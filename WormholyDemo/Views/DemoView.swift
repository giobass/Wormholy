// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import SwiftUI

struct DemoView: View {
    // MARK: - Body

    var body: some View {
        TabView {
            RequestsDemoView()
                .tabItem {
                    Label("HTTP Requests", systemImage: "list.bullet.rectangle")
                }

            WebSocketDemoView()
                .tabItem {
                    Label("WebSocket", systemImage: "bolt.horizontal")
                }
        }
    }
}

extension View {
    // MARK: - Inspector

    func inspectorToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Inspector", systemImage: "ladybug") {
                    NotificationCenter.default.post(name: NSNotification.Name(rawValue: "wormholy_fire"), object: nil)
                }
                .tint(.accentColor)
            }
        }
    }
}

#Preview {
    DemoView()
}
