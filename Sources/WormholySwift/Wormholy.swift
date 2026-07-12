//
//  Wormholy.swift
//  Wormholy
//
//  Created by Paolo Musolino.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import Foundation
import UIKit
import SwiftUI

public class Wormholy: NSObject
{
    /// Hosts that will be ignored from being recorded.
    ///
    /// Uses suffix matching on the request host, and applies to both HTTP requests
    /// and WebSocket connections.
    @objc public static var ignoredHosts: [String] {
        get { return CustomHTTPProtocol.ignoredHosts }
        set { CustomHTTPProtocol.ignoredHosts = newValue }
    }
    
    /// Limit the logging count.
    ///
    /// The configured value is applied separately to HTTP requests and WebSocket connections.
    @objc public static var limit: NSNumber? {
        get {
            Task { @MainActor in
                return Storage.limit
            }
            return nil // Placeholder return, adjust as needed
        }
        set {
            Task { @MainActor in
                Storage.limit = newValue
            }
        }
    }

    /// Limit the number of messages retained for each WebSocket connection.
    ///
    /// When the limit is reached, Wormholy removes the oldest messages and keeps
    /// the most recent ones.
    ///
    /// Defaults to `nil`, which keeps the complete message history for each captured connection.
    @objc public static var webSocketMessageLimit: NSNumber? {
        get {
            Task { @MainActor in
                return Storage.webSocketMessageLimit
            }
            return nil // Placeholder return, adjust as needed
        }
        set {
            Task { @MainActor in
                Storage.webSocketMessageLimit = newValue
            }
        }
    }
    
    /// Default filter for the search box
    ///
    @objc public static var defaultFilter: String? {
        get {
            Task { @MainActor in
                return Storage.defaultFilter
            }
            return nil // Placeholder return, adjust as needed
        }
        set {
            Task { @MainActor in
                Storage.defaultFilter = newValue
            }
        }
    }
    
    // Flag to determine if Wormholy is enabled
    internal static var isEnabled: Bool = true
    
    /// Method to initialize Wormholy
    @objc public static func swiftyLoad() {
        NotificationCenter.default.addObserver(forName: fireWormholy, object: nil, queue: nil) { (notification) in
            Wormholy.presentWormholyFlow()
        }
    }
    
    /// Method to initialize Wormholy with default settings
    @objc public static func swiftyInitialize() {
        if self == Wormholy.self {
            Wormholy.setEnabled(isEnabled)
        }
    }
    
    /// Toggles the tracking of HTTP requests in Wormholy.
    /// Note: This function does not affect the shake gesture activation of Wormholy. 
    /// To control the shake gesture, use the `shakeEnabled` property.
    @objc public static func setEnabled(_ enable: Bool) {
        isEnabled = enable
        if enable {
            URLProtocol.registerClass(CustomHTTPProtocol.self)
        } else {
            URLProtocol.unregisterClass(CustomHTTPProtocol.self)
        }
    }
    
    /// Method to enable or disable Wormholy for a specific session configuration
    @objc public static func setEnabled(_ enable: Bool, sessionConfiguration: URLSessionConfiguration) {
        guard sessionConfiguration.responds(to: #selector(getter: URLSessionConfiguration.protocolClasses)) &&
                sessionConfiguration.responds(to: #selector(setter: URLSessionConfiguration.protocolClasses)) else {
            print("[Wormholy] is only available when running on iOS16+")
            return
        }
        
        var urlProtocolClasses = sessionConfiguration.protocolClasses ?? []
        let protoCls = CustomHTTPProtocol.self
        
        if enable {
            if !urlProtocolClasses.contains(where: { $0 == protoCls }) {
                urlProtocolClasses.insert(protoCls, at: 0)
            }
        } else {
            if let index = urlProtocolClasses.firstIndex(where: { $0 == protoCls }) {
                urlProtocolClasses.remove(at: index)
            }
        }
        sessionConfiguration.protocolClasses = urlProtocolClasses
    }

    /// Toggles the tracking of native `URLSessionWebSocketTask` traffic in Wormholy.
    /// Independent from `setEnabled`, since WebSocket swizzling intercepts every
    /// `send`/`receive` call and some apps may want to opt out of that overhead
    /// even while HTTP tracking stays on.
    ///
    /// Delegate-backed sessions are proxied when they are created so open/close
    /// events can be recorded whenever WebSocket tracking is enabled.
    @objc public static func setWebSocketEnabled(_ enable: Bool) {
        if enable {
            WebSocketInterceptor.install()
        }
        WebSocketInterceptor.isEnabled = enable
    }

    // MARK: - Navigation
    static func presentWormholyFlow() {
        // Check if RequestsView is already presented
        if let currentViewController = UIViewController.currentViewController(),
           currentViewController is UIHostingController<RequestsView> {
            // RequestsView is already presented, do nothing
            return
        }

        // Present RequestsView as a SwiftUI view
        let requestsView = RequestsView()
        let hostingController = UIHostingController(rootView: requestsView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.detents = [.large()]
        }
        UIViewController.currentViewController()?.present(hostingController, animated: true, completion: nil)
    }
    
    @objc public static var shakeEnabled: Bool = {
        let key = "WORMHOLY_SHAKE_ENABLED"
        
        if let environmentVariable = ProcessInfo.processInfo.environment[key] {
            return environmentVariable != "NO"
        }
        
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        if let arg = arguments[key] {
            switch arg {
            case let boolean as Bool: return boolean
            case let string as NSString: return string.boolValue
            case let number as NSNumber: return number.boolValue
            default: break
            }
        }
        
        return true
    }()
}

/// WormholyConstructor calls this to initialize library
extension Wormholy {
    
    @objc static func applicationDidFinishLaunching() {
        initializeAction
    }
    
    private static let initializeAction: Void = {
        swiftyLoad()
        swiftyInitialize()
    }()
    
    // Method to expose isEnabled to Objective-C, for NSURLSessionConfiguration+Wormholy
    @objc public static func isWormholyEnabled() -> Bool {
        return isEnabled
    }
}
