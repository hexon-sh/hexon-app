import AppIntents

struct HexonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendSOLIntent(),
            phrases: [
                "Transfer token with \(.applicationName)",
                "Transfer crypto with \(.applicationName)",
                "Send token using \(.applicationName)"
            ],
            shortTitle: "Transfer Token",
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
