//
//  AppDelegate.swift
//  WormholyDemo
//
//  Created by Paolo Musolino on 11/04/18.
//  Copyright © 2018 Wormholy. All rights reserved.
//

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
