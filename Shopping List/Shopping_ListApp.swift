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
    @UIApplicationDelegateAdaptor(ShoppingListAppDelegate.self) private var appDelegate
    @StateObject private var shareManager = ShoppingListShareManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(shareManager)
        }
        .modelContainer(for: [ShopItem.self, ShoppingListEntry.self, ViewSettings.self])
    }
}
