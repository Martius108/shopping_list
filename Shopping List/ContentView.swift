//
//  ContentView.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext: ModelContext
    @State private var filteredSuggestions: [String] = []
    @StateObject var dataManager = ShopDataManager()
    @State private var newItem: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Image
                Image(.image2)
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 16) {
                    // Input field for new items
                    NewItemInputView(
                        dataManager: dataManager, newItem: $newItem, filteredSuggestions: $filteredSuggestions
                    )

                    // Lists
                    VStack(spacing: 12) {
                        List {
                            ShopItemsView(dataManager: dataManager)
                            BoughtItemsView(dataManager: dataManager)
                        }
                        .scrollContentBackground(.hidden)
                    }

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
