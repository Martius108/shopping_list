//
//  InputItemView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// View for entering new shopping list items and displaying suggestions
struct InputItemView: View {
    
    // Access the model context to interact with the local database
    @Environment(\.modelContext) private var modelContext
    // Query to fetch all shopping items, sorted by name
    @Query(sort: \ShopItem.name) private var items: [ShopItem]
    // Access the current color scheme (light/dark mode)
    @Environment(\.colorScheme) var colorScheme
    // Add a focus to the text field (to make the keyboard disappear)
    @FocusState private var isTextFieldFocused: Bool
    // Bindings to settings and user input states
    @Binding var settings: ViewSettings?
    @Binding var newItem: String
    @Binding var filteredSuggestions: [String]
    var contentWidth: CGFloat

    var body: some View {

        // Text input field for adding a new item
        TextField("", text: $newItem)
            .focused($isTextFieldFocused)
            .padding()
            .background(elementColor(darkModeColor: .black, lightModeColor: .white))
            .frame(maxWidth: contentWidth, maxHeight: 40)
            .overlay(
                Text("I need")
                    .foregroundStyle(.secondary)
                    .opacity(newItem.isEmpty ? 1 : 0)
                    .padding(.leading, 14)
                    .allowsHitTesting(false),
                alignment: .leading
            )
            .font(.system(size: 18))
            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            .cornerRadius(8)
            .padding(.horizontal)
            .onChange(of: newItem) {
                let displayName = ShoppingListLogic.displayName(for: newItem)
                if newItem != displayName {
                    newItem = displayName
                }

                // Update suggestions based on current input
                let items = (try? modelContext.fetch(FetchDescriptor<ShopItem>())) ?? []
                filteredSuggestions = ShoppingListLogic.suggestions(
                    for: newItem,
                    from: items.map(\.name)
                )
            }
            .onSubmit {
                addOrReactivateItem(named: newItem)
            }

        // Display up to 3 suggestions below the input field
        if !filteredSuggestions.isEmpty {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(filteredSuggestions.prefix(3).enumerated()), id: \.element) { index, suggestion in
                    Text(suggestion)
                        .padding(.horizontal)
                        .padding(.vertical, 9)
                        .font(.system(size: 17))
                        .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                        .onTapGesture {
                            addOrReactivateItem(named: suggestion)
                            isTextFieldFocused = false
                        }
                    // Insert a divider between suggestions
                    if index < filteredSuggestions.prefix(3).count - 1 {
                        Divider()
                            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .background(elementColor(darkModeColor: .black, lightModeColor: .white))
            .cornerRadius(8)
        }
    }

    private func addOrReactivateItem(named value: String) {
        let newItemName = ShoppingListLogic.displayName(for: value)
        guard !newItemName.isEmpty else { return }

        do {
            let allItems = try modelContext.fetch(FetchDescriptor<ShopItem>())
            if let match = allItems.first(where: { ShoppingListLogic.matches($0.name, newItemName) }) {
                if match.isBought {
                    match.isBought = false
                    match.createdAt = Date()
                    try modelContext.save()
                }
                clearInput()
                return
            }

            let item = ShopItem(name: newItemName, amount: 1, isBought: false, createdAt: Date())
            modelContext.insert(item)
            try modelContext.save()
            clearInput()
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }

    private func clearInput() {
        newItem = ""
        filteredSuggestions = []
    }
    
    // Utility function to return themed color based on user settings and system theme
    private func themedColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        guard let settings = settings else {
            return lightModeColor
        }
        
        let theme = settings.themeMode

        switch ThemeMode(rawValue: theme) {
        case .dark:
            return darkModeColor
        case .light:
            return lightModeColor
        case .system:
            return colorScheme == .dark
                ? darkModeColor
                : lightModeColor
        case nil:
            return lightModeColor
        }
    }

    private func elementColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        themedColor(darkModeColor: darkModeColor, lightModeColor: lightModeColor)
            .opacity(settings?.elementOpacity ?? 1)
    }
}
