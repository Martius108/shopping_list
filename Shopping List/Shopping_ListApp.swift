//
//  Shopping_ListApp.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import SwiftUI
import SwiftData

@main
struct Shopping_ListApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: ShopItem.self)
    }
}
