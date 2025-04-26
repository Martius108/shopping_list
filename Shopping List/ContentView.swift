//
//  ContentView.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import SwiftUI
import SwiftData

// Separate view for a fixed-size background
struct FixedBackgroundView: View {

    var body: some View {
        // Use geometry reader to avoid changes of the image when keyboard is toggled
        GeometryReader { geometry in
            Image(.image2)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .edgesIgnoringSafeArea(.all) // Ensure the background covers the entire screen
    }
}

// Main view for the shopping list
struct ContentView: View {
    
    // Set up all necessary variables and state properties
    @Environment(\.modelContext) private var modelContext: ModelContext
    // Set up a query to react onto changes in the data container
    @Query(sort: \ShopItem.name) var itemsList: [ShopItem]
    
    @State private var filteredSuggestions: [String] = []
    @State private var newItem: String = ""

    private func removeDuplicateItems() {
        var seenNames = Set<String>()
        for item in itemsList {
            let normalizedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seenNames.contains(normalizedName) {
                modelContext.delete(item)
            } else {
                seenNames.insert(normalizedName)
            }
        }
        try? modelContext.save()
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Fixed background view placed in the back
                FixedBackgroundView()

                VStack(spacing: 16) {
                    // Input text field for items to buy
                    InputItemView(
                        newItem: $newItem, filteredSuggestions: $filteredSuggestions
                    )
                    // Scroll view holding the lists for the items
                    ScrollView {
                        VStack(spacing: 0) {
                            ShopItemsView(items: itemsList)
                            BoughtItemsView(items: itemsList)
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                removeDuplicateItems() // Just in case duplicates did appear
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ShopItem.self) // Just for preview purposes
}
