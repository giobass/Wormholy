// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT
import Foundation
import ObjectiveC

private typealias WebSocketTaskWithURLFactory = (URLSession) -> (URL) -> URLSessionWebSocketTask
private typealias WebSocketTaskWithRequestFactory = (URLSession) -> (URLRequest) -> URLSessionWebSocketTask

internal enum WebSocketConfiguration {
    private static let lock = NSLock()
    private static var storedIsEnabled = false
    private static var storedMessageLimit: NSNumber?

    internal static var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedIsEnabled
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedIsEnabled = newValue
        }
    }

    internal static var messageLimit: NSNumber? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedMessageLimit
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedMessageLimit = newValue
        }
    }
}

/// Swizzles URLSession's WebSocket factory methods and URLSessionWebSocketTask's
/// send/receive/cancel methods to capture WebSocket traffic without requiring
/// any change in the host app's code.
///
/// Swizzling `send(_:completionHandler:)` and `receive(completionHandler:)` also covers
/// their `async throws` counterparts, since Foundation's async overlay for these APIs
/// calls straight into the completion-handler based implementations under the hood.
internal enum WebSocketInterceptor {
    /// Controls whether swizzled methods actually record traffic. The swizzle itself,
    /// once installed, is never removed - this mirrors how HTTP tracking is toggled
    /// elsewhere in Wormholy (see `Wormholy.setEnabled`).
    internal static var isEnabled: Bool {
        get { WebSocketConfiguration.isEnabled }
        set { WebSocketConfiguration.isEnabled = newValue }
    }

    private static var isInstalled = false
    private static var swizzledConcreteClasses = Set<ObjectIdentifier>()
    private static let swizzleLock = NSLock()

    internal static func install() {
        swizzleLock.lock()
        defer { swizzleLock.unlock() }
        guard !isInstalled else { return }

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:) as WebSocketTaskWithURLFactory),
                                       #selector(URLSession.wormholy_webSocketTaskWithURL(_:)))

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:protocols:)),
                                       #selector(URLSession.wormholy_webSocketTaskWithURL(_:protocols:)))

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:) as WebSocketTaskWithRequestFactory),
                                       #selector(URLSession.wormholy_webSocketTaskWithRequest(_:)))

        // `send`, `receive`, and `cancel(with:reason:)` aren't swizzled here: `URLSession`'s
        // WebSocket factories return an instance of a private concrete subclass that actually
        // implements them, not the public `URLSessionWebSocketTask` class - swizzling the
        // public class's method table would have no effect on those instances. They're
        // swizzled lazily per real class instead, see `ensureSwizzledForActualClass`.
        isInstalled = true
    }

    internal static func installSessionDelegateProxy() {
        guard let swizzlerClass = NSClassFromString("WHWebSocketSessionSwizzler") as? NSObject.Type else { return }
        let selector = NSSelectorFromString("wormholy_installWebSocketDelegateProxy")
        guard swizzlerClass.responds(to: selector) else { return }
        _ = swizzlerClass.perform(selector)
    }

    private static func runOnMainActorSync(_ operation: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(operation)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(operation)
            }
        }
    }

    fileprivate static func attachModel(to task: URLSessionWebSocketTask,
                                        url: URL?,
                                        headers: [String: String],
                                        protocols: [String]) {
        guard isEnabled, let url = url else { return }
        guard let host = url.host,
              CustomHTTPProtocol.ignoredHosts.filter({ host.hasSuffix($0) }).isEmpty else {
            return
        }

        ensureSwizzledForActualClass(of: task)

        runOnMainActorSync {
            // Some factory overloads delegate to another one internally for the same task,
            // which would otherwise attach a second, orphaned model here.
            if let existing = task.wormholyModel {
                existing.refineConnectionMetadataIfNeeded(url: url, headers: headers, protocols: protocols)
                return
            }

            let model = WebSocketModel(url: url.absoluteString,
                                        host: url.host,
                                        scheme: url.scheme,
                                        requestHeaders: headers,
                                        requestedProtocols: protocols)
            task.wormholyModel = model
            Storage.shared.saveWebSocketConnection(model)
        }
    }

    /// Swizzles `cancel(with:reason:)` (Swift side) and triggers the Objective-C swizzle of
    /// `send`/`receive` (see URLSessionWebSocketTask+Wormholy.m) on the task's actual runtime
    /// class, the first time that class is seen. Idempotent per class.
    private static func ensureSwizzledForActualClass(of task: URLSessionWebSocketTask) {
        guard let concreteClass = object_getClass(task) else { return }
        let key = ObjectIdentifier(concreteClass)

        swizzleLock.lock()
        defer { swizzleLock.unlock() }
        guard !swizzledConcreteClasses.contains(key) else { return }

        wormholySwizzleInstanceMethod(concreteClass,
                                       #selector(URLSessionWebSocketTask.cancel(with:reason:)),
                                       #selector(URLSessionWebSocketTask.wormholy_cancel(with:reason:)))

        if let swizzlerClass = NSClassFromString("WHWebSocketTaskSwizzler") as? NSObject.Type {
            let selector = NSSelectorFromString("wormholy_ensureSwizzledFor:")
            if swizzlerClass.responds(to: selector) {
                _ = swizzlerClass.perform(selector, with: task)
            }
        }

        swizzledConcreteClasses.insert(key)
    }
}

private func wormholySwizzleInstanceMethod(_ affectedClass: AnyClass, _ original: Selector, _ swizzled: Selector) {
    guard let originalMethod = class_getInstanceMethod(affectedClass, original),
          let swizzledMethod = class_getInstanceMethod(affectedClass, swizzled) else {
        return
    }

    let didAddMethod = class_addMethod(affectedClass,
                                        original,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod))
    if didAddMethod {
        class_replaceMethod(affectedClass,
                             swizzled,
                             method_getImplementation(originalMethod),
                             method_getTypeEncoding(originalMethod))
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

extension URLSession {
    @objc dynamic func wormholy_webSocketTaskWithURL(_ url: URL) -> URLSessionWebSocketTask {
        let task = wormholy_webSocketTaskWithURL(url)
        WebSocketInterceptor.attachModel(to: task, url: url, headers: [:], protocols: [])
        return task
    }

    @objc dynamic func wormholy_webSocketTaskWithURL(_ url: URL, protocols: [String]) -> URLSessionWebSocketTask {
        let task = wormholy_webSocketTaskWithURL(url, protocols: protocols)
        WebSocketInterceptor.attachModel(to: task, url: url, headers: [:], protocols: protocols)
        return task
    }

    @objc dynamic func wormholy_webSocketTaskWithRequest(_ request: URLRequest) -> URLSessionWebSocketTask {
        let task = wormholy_webSocketTaskWithRequest(request)
        WebSocketInterceptor.attachModel(to: task,
                                         url: request.url,
                                         headers: request.allHTTPHeaderFields ?? [:],
                                         protocols: [])
        return task
    }
}

extension URLSessionWebSocketTask {
    private static var wormholyModelKey: UInt8 = 0

    internal var wormholyModel: WebSocketModel? {
        get { objc_getAssociatedObject(self, &Self.wormholyModelKey) as? WebSocketModel }
        set { objc_setAssociatedObject(self, &Self.wormholyModelKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @objc dynamic func wormholy_cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if WebSocketInterceptor.isEnabled {
            WHWebSocketRecorder.recordClosed(self, closeCode: closeCode, reason: reason)
        }
        wormholy_cancel(with: closeCode, reason: reason)
    }
}
