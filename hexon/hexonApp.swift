//
//  hexonApp.swift
//  hexon
//
//  Created by CodeParth on 18/05/26.
//

import SwiftUI
import PrivySDK

let privy: Privy = PrivySdk.initialize(config: PrivyConfig(
    appId: "cmpbajp75008d0cl1g0de2e3h",
    appClientId: "client-WY6ZXQx5Rii7eGJ3FMNd8XBZ8u995jUfmx9CEsDoRmNmf"
))

@main
struct hexonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
