import Foundation

@Observable
class WalletWebSocket {
    var isConnected = false
    var onNewActivity: (() -> Void)?

    private var task: URLSessionWebSocketTask?
    private var generation = 0

    func connect(address: String, network: SolanaNetwork) {
        disconnect()
        generation += 1
        let gen = generation
        let url = URL(string: network.wsURL)!
        let newTask = URLSession.shared.webSocketTask(with: url)
        task = newTask
        newTask.resume()

        // Verify the connection with a ping before subscribing
        newTask.sendPing { [weak self] error in
            guard let self, self.generation == gen else { return }
            if error == nil {
                DispatchQueue.main.async { self.isConnected = true }
                self.sendSubscribe(address: address, task: newTask, gen: gen)
                self.listen(task: newTask, gen: gen)
            } else {
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }

    func disconnect() {
        generation += 1
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func sendSubscribe(address: String, task: URLSessionWebSocketTask, gen: Int) {
        guard generation == gen else { return }
        let msg = """
        {"jsonrpc":"2.0","id":1,"method":"accountSubscribe","params":["\(address)",{"encoding":"jsonParsed","commitment":"confirmed"}]}
        """
        task.send(.string(msg)) { _ in }
    }

    private func listen(task: URLSessionWebSocketTask, gen: Int) {
        guard generation == gen else { return }
        task.receive { [weak self] result in
            guard let self, self.generation == gen else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message,
                   text.contains("accountNotification") {
                    DispatchQueue.main.async { self.onNewActivity?() }
                }
                self.listen(task: task, gen: gen)
            case .failure:
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }
}
