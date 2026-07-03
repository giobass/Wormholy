//
//  WebSocketCellView.swift
//  Wormholy
//
//  Created by Giovanni Bassolino on 03/07/26.
//

import SwiftUI

internal struct WebSocketCellView: View {
    @ObservedObject var connection: WebSocketModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.state.title.uppercased())
                    .font(.caption)
                    .bold()
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Colors.WebSocket.getStateColor(connection.state), lineWidth: 0.5))
                    .foregroundColor(Colors.WebSocket.getStateColor(connection.state))

                Text("\(connection.messages.count) msg")
                    .font(.footnote)
            }

            Text(connection.url)
                .font(.subheadline)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WebSocketCellView_Previews: PreviewProvider {
    static var previews: some View {
        let openConnection = WebSocketModel(url: "wss://ws.postman-echo.com/raw")
        openConnection.markOpened()
        openConnection.addMessage(direction: .sent, message: .string("hello"))
        openConnection.addMessage(direction: .received, message: .string("hello back"))

        let closedConnection = WebSocketModel(url: "wss://ws.postman-echo.com/raw/very/long/path/that/wraps")
        closedConnection.markOpened()
        closedConnection.markClosed(code: .normalClosure, reason: nil)

        return VStack(alignment: .leading, spacing: 12) {
            WebSocketCellView(connection: openConnection)
            WebSocketCellView(connection: closedConnection)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
