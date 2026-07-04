//
//  DemoView.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

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
            }
        }
    }
}

#Preview {
    DemoView()
}
