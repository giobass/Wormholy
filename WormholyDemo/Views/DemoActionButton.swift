//
//  DemoActionButton.swift
//  WormholyDemo
//
//  Created by Giovanni Bassolino on 04/07/26.
//  Copyright © 2018 Wormholy. All rights reserved.
//

import SwiftUI

struct DemoActionButton: View {
    // MARK: - Properties

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHighlighted = false

    let title: String
    let systemImage: String
    let tint: Color
    let role: ButtonRole?
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        tint: Color = .accentColor,
        role: ButtonRole? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.role = role
        self.isLoading = isLoading
        self.action = action
    }

    // MARK: - Body

    var body: some View {
        Button(role: role) {
            showTapFeedback()
            action()
        } label: {
            Label {
                Text(title)
            } icon: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 8)
            .foregroundStyle(isLoading ? .secondary : foregroundStyle)
            .opacity(isHighlighted ? 0.55 : 1)
            .scaleEffect(isHighlighted ? 0.98 : 1, anchor: .leading)
        }
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }

    // MARK: - Actions

    private func showTapFeedback() {
        isHighlighted = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isHighlighted = false
        }
    }

    // MARK: - Style

    private var foregroundStyle: Color {
        isEnabled ? tint : .secondary
    }
}
