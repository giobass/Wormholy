// Copyright (c) 2026 Wormholy contributors
// SPDX-License-Identifier: MIT

import Foundation

final class HTTPDemoClient {
    // MARK: - Properties

    static let sharedInstance = HTTPDemoClient(cachePolicy: .reloadIgnoringLocalCacheData)

    fileprivate static let demoErrorDomain = "com.codeido.Wormholy-Demo-iOS"

    private let session: URLSession

    // MARK: - Init

    init(cachePolicy: URLRequest.CachePolicy) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = cachePolicy
        configuration.httpAdditionalHeaders = ["Accept-Language": "en"]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Requests

    func getPost(id: Int, completion: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        perform(.getPost(id: id), completion: completion, failure: failure)
    }

    func newPost(userId: Int,
                 title: String,
                 body: String,
                 completion: @escaping () -> Void,
                 failure: @escaping (Error) -> Void) {
        perform(.newPost(userId: userId, title: title, body: body), completion: completion, failure: failure)
    }

    func getWrongURL(completion: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        perform(.wrongURL, completion: completion, failure: failure)
    }

    func getPhotosList(completion: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        perform(.photos, completion: completion, failure: failure)
    }

    // MARK: - Networking

    private func perform(_ endpoint: Endpoint,
                         completion: @escaping () -> Void,
                         failure: @escaping (Error) -> Void) {
        session.dataTask(with: endpoint.urlRequest) { _, response, error in
            if let error {
                DispatchQueue.main.async {
                    failure(error)
                }
                return
            }

            if let error = response?.httpValidationError {
                DispatchQueue.main.async {
                    failure(error)
                }
                return
            }

            DispatchQueue.main.async {
                completion()
            }
        }.resume()
    }
}

private enum Endpoint {
    // MARK: - Cases

    case getPost(id: Int)
    case newPost(userId: Int, title: String, body: String)
    case wrongURL
    case photos

    // MARK: - Request

    var urlRequest: URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = payload?.jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static let baseURL = URL(string: "https://jsonplaceholder.typicode.com")!

    // MARK: - Components

    private var method: String {
        switch self {
        case .newPost:
            return "POST"
        case .getPost, .wrongURL, .photos:
            return "GET"
        }
    }

    private var path: String {
        switch self {
        case .getPost(let id):
            return "/posts/\(id)"
        case .newPost:
            return "/posts/"
        case .wrongURL:
            return "/wrongURL/"
        case .photos:
            return "/photos"
        }
    }

    private var payload: [String: Any]? {
        switch self {
        case .newPost(let userId, let title, let body):
            return ["userId": userId, "title": title, "body": body]
        case .getPost, .wrongURL, .photos:
            return nil
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    // MARK: - JSON

    var jsonData: Data? {
        guard JSONSerialization.isValidJSONObject(self) else {
            return nil
        }

        do {
            return try JSONSerialization.data(withJSONObject: self, options: .prettyPrinted)
        } catch {
            print("Error! Could not create JSON for server payload: \(error.localizedDescription)")
            return nil
        }
    }
}

private extension URLResponse {
    // MARK: - Validation

    var httpValidationError: Error? {
        guard let response = self as? HTTPURLResponse else {
            return nil
        }

        let acceptableStatusCodes = 200..<300
        guard !acceptableStatusCodes.contains(response.statusCode) else {
            return nil
        }

        let failureReason = "Response status code was unacceptable: \(response.statusCode)"
        return NSError(
            domain: HTTPDemoClient.demoErrorDomain,
            code: response.statusCode,
            userInfo: [
                NSLocalizedFailureReasonErrorKey: failureReason,
                "StatusCode": response.statusCode
            ]
        )
    }
}
