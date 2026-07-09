//
//  WebSocketInterceptor.swift
//  Wormholy
//
//  Created by Giovanni Bassolino on 03/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//
import Foundation
import ObjectiveC

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
    internal static var isEnabled: Bool = false

    private static var isInstalled = false
    private static var swizzledConcreteClasses = Set<ObjectIdentifier>()
    private static let swizzleLock = NSLock()

    internal static func install() {
        swizzleLock.lock()
        let alreadyInstalled = isInstalled
        if !alreadyInstalled { isInstalled = true }
        swizzleLock.unlock()
        guard !alreadyInstalled else { return }

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:) as (URLSession) -> (URL) -> URLSessionWebSocketTask),
                                       #selector(URLSession.wormholy_webSocketTaskWithURL(_:)))

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:protocols:)),
                                       #selector(URLSession.wormholy_webSocketTaskWithURL(_:protocols:)))

        wormholySwizzleInstanceMethod(URLSession.self,
                                       #selector(URLSession.webSocketTask(with:) as (URLSession) -> (URLRequest) -> URLSessionWebSocketTask),
                                       #selector(URLSession.wormholy_webSocketTaskWithRequest(_:)))

        // `send`, `receive`, and `cancel(with:reason:)` aren't swizzled here: `URLSession`'s
        // WebSocket factories return an instance of a private concrete subclass that actually
        // implements them, not the public `URLSessionWebSocketTask` class - swizzling the
        // public class's method table would have no effect on those instances. They're
        // swizzled lazily per real class instead, see `ensureSwizzledForActualClass`.
    }

    fileprivate static func attachModel(to task: URLSessionWebSocketTask, url: URL?, headers: [String: String], protocols: [String]) {
        guard isEnabled, let url = url else { return }
        guard let host = url.host, CustomHTTPProtocol.ignoredHosts.filter({ host.hasSuffix($0) }).isEmpty else { return }

        ensureSwizzledForActualClass(of: task)

        // Some factory overloads delegate to another one internally for the same task
        // (see `WebSocketModel.preferURLIfMoreAccurate`), which would otherwise attach a
        // second, orphaned model here. Only the first call creates a Storage entry.
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
        Task { @MainActor in
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
        let alreadySwizzled = swizzledConcreteClasses.contains(key)
        if !alreadySwizzled { swizzledConcreteClasses.insert(key) }
        swizzleLock.unlock()
        guard !alreadySwizzled else { return }

        wormholySwizzleInstanceMethod(concreteClass,
                                       #selector(URLSessionWebSocketTask.cancel(with:reason:)),
                                       #selector(URLSessionWebSocketTask.wormholy_cancel(with:reason:)))

        if let swizzlerClass = NSClassFromString("WHWebSocketTaskSwizzler") as? NSObject.Type {
            let selector = NSSelectorFromString("wormholy_ensureSwizzledFor:")
            if swizzlerClass.responds(to: selector) {
                _ = swizzlerClass.perform(selector, with: task)
            }
        }
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
        WebSocketInterceptor.attachModel(to: task, url: request.url, headers: request.allHTTPHeaderFields ?? [:], protocols: [])
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
            Task { @MainActor in
                wormholyModel?.markClosed(code: closeCode, reason: reason)
            }
        }
        wormholy_cancel(with: closeCode, reason: reason)
    }
}

/// Bridge called from the Objective-C swizzling of `send(_:completionHandler:)` and
/// `receive(completionHandler:)` (see URLSessionWebSocketTask+Wormholy.m), where the
/// message payload has already been unwrapped into plain Foundation types because
/// `URLSessionWebSocketTask.Message` isn't representable in `@objc`.
@objc(WHWebSocketRecorder)
public final class WHWebSocketRecorder: NSObject {
    @objc public static var isEnabled: Bool { WebSocketInterceptor.isEnabled }

    @objc public static func recordSentText(_ task: URLSessionWebSocketTask, text: String) {
        Task { @MainActor in
            task.wormholyModel?.addMessage(direction: .sent, message: .string(text))
        }
    }

    @objc public static func recordSentData(_ task: URLSessionWebSocketTask, data: Data) {
        Task { @MainActor in
            task.wormholyModel?.addMessage(direction: .sent, message: .data(data))
        }
    }

    @objc public static func recordReceivedText(_ task: URLSessionWebSocketTask, text: String) {
        Task { @MainActor in
            task.wormholyModel?.addMessage(direction: .received, message: .string(text))
        }
    }

    @objc public static func recordReceivedData(_ task: URLSessionWebSocketTask, data: Data) {
        Task { @MainActor in
            task.wormholyModel?.addMessage(direction: .received, message: .data(data))
        }
    }

    @objc public static func recordOpened(_ task: URLSessionWebSocketTask, protocol negotiatedProtocol: String?) {
        Task { @MainActor in
            task.wormholyModel?.markOpened(protocol: negotiatedProtocol)

            // Foundation populates the task's `response` with the HTTP handshake's 101
            // Switching Protocols response (headers included) once the socket opens.
            if let httpResponse = task.response as? HTTPURLResponse {
                let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                    if let key = entry.key as? String, let value = entry.value as? String {
                        result[key] = value
                    }
                }
                task.wormholyModel?.updateResponseHeaders(headers)
            }
        }
    }

    @objc public static func recordClosed(_ task: URLSessionWebSocketTask,
                                          closeCode: URLSessionWebSocketTask.CloseCode,
                                          reason: Data?) {
        Task { @MainActor in
            task.wormholyModel?.markClosed(code: closeCode, reason: reason)
        }
    }

    @objc public static func recordError(_ task: URLSessionWebSocketTask, error: Error) {
        Task { @MainActor in
            task.wormholyModel?.markError(error)
        }
    }
}
