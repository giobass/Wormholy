//
//  WormholyDemoApp.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

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
