// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct WormholyDemoApp: App {
    // MARK: - Properties

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            DemoView()
        }
    }
}
