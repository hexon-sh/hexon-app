import AppIntents

struct HexonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendSOLIntent(),
            phrases: [
                "Transfer SOL with \(.applicationName)",
                "Transfer crypto with \(.applicationName)",
                "Send SOL using \(.applicationName)"
            ],
            shortTitle: "Transfer SOL",
            systemImageName: "arrow.up.circle.fill"
        )
        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "Check my \(.applicationName) balance",
                "Show my \(.applicationName) balance",
                "What is my \(.applicationName) balance"
            ],
            shortTitle: "Check Balance",
            systemImageName: "dollarsign.circle.fill"
        )
    }
}
