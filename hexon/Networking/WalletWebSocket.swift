import Foundation

@Observable
class WalletWebSocket {
    var isConnected = false
    var onNewActivity: (() -> Void)?

    private var task: URLSessionWebSocketTask?

    func connect(address: String, network: SolanaNetwork) {
        disconnect()
        let url = URL(string: network.wsURL)!
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        isConnected = true
        sendSubscribe(address: address)
        listen()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func sendSubscribe(address: String) {
        let msg = """
        {"jsonrpc":"2.0","id":1,"method":"accountSubscribe","params":["\(address)",{"encoding":"jsonParsed","commitment":"confirmed"}]}
        """
        task?.send(.string(msg)) { _ in }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   text.contains("accountNotification") {
                    DispatchQueue.main.async { self.onNewActivity?() }
                }
                self.listen()
            case .failure:
                self.isConnected = false
            }
        }
    }
}
