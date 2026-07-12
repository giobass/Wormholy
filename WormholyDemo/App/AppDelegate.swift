// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import UIKit
import WormholySwift

final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - App Configuration

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Limit the number of API requests stored
        Wormholy.limit = 100

        // HTTP tracking is enabled by default. WebSocket tracking is opt-in.
        Wormholy.setWebSocketEnabled(true)

        return true
    }
}
