//
//  RequestsDemoViewModel.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import Foundation

@MainActor
final class RequestsDemoViewModel: ObservableObject {
    // MARK: - Properties

    static let automaticHTTPInterval: TimeInterval = 4

    @Published var isAutomaticHTTPRunning = false

    // MARK: - Status

    var automaticHTTPStatus: String {
        isAutomaticHTTPRunning
            ? "Automatic HTTP traffic is running every \(automaticHTTPIntervalText)."
            : "Automatic HTTP traffic is paused."
    }

    var automaticHTTPIntervalText: String {
        let interval = Self.automaticHTTPInterval

        if interval.rounded() == interval {
            return "\(Int(interval)) seconds"
        } else {
            return "\(interval) seconds"
        }
    }

    // MARK: - Automatic Traffic

    func logAutomaticHTTPState() {
        if isAutomaticHTTPRunning {
            print("API: Automatic traffic started (every \(automaticHTTPIntervalText))")
        } else {
            print("API: Automatic traffic stopped")
        }
    }

    func generateAutomaticTrafficIfNeeded() {
        guard isAutomaticHTTPRunning else { return }

        getPost(id: randomNumber(max: 128))
        getPhotos()
    }

    // MARK: - Request Actions

    func getPost(id: Int = 1) {
        HTTPDemoClient.sharedInstance.getPost(id: id) {
            print("API: Get post")
        } failure: { error in
            print("ERROR: api Get post - \(error.localizedDescription)")
        }
    }

    func newRandomPost() {
        HTTPDemoClient.sharedInstance.newPost(userId: randomNumber(max: 5000),
                                              title: randomText(length: 128),
                                              body: randomText(length: 5000)) {
            print("API: New post")
        } failure: { error in
            print("ERROR: api New post - \(error.localizedDescription)")
        }
    }

    func getWrongURL() {
        HTTPDemoClient.sharedInstance.getWrongURL {
            print("API: Wrong URL")
        } failure: { error in
            print("ERROR: api Wrong URL - \(error.localizedDescription)")
        }
    }

    func getPhotos() {
        HTTPDemoClient.sharedInstance.getPhotosList {
            print("API: Get photos")
        } failure: { error in
            print("ERROR: api Get photos - \(error.localizedDescription)")
        }
    }

    // MARK: - Random Data

    private func randomNumber(max: Int) -> Int {
        Int.random(in: 0..<max)
    }

    private func randomText(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890 ")
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}
