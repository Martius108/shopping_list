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
    // Bindings to settings and user input states
    @Binding var settings: ViewSettings?
    @Binding var newItem: String
    @Binding var filteredSuggestions: [String]

    var body: some View {

        // Text input field for adding a new item
        TextField("", text: $newItem)
            .padding()
            .background(themedColor(darkModeColor: .black, lightModeColor: .white))
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width, maxHeight: 40)
            .overlay(
                // Placeholder text shown when input is empty
                Text("I need")
                    .foregroundColor(themedColor(darkModeColor: .gray, lightModeColor: .gray))
                    .opacity(newItem.isEmpty ? 1 : 0)
                    .padding(.leading, 14),
                alignment: .leading
            )
            .font(.system(size: 18))
            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            .cornerRadius(8)
            .padding(.horizontal)
            .onChange(of: newItem) {
                // Capitalize the first letter of the input
                newItem = newItem.prefix(1).uppercased() + newItem.dropFirst()

                // Update suggestions based on current input
                let suggestions = try? modelContext.fetch(FetchDescriptor<ShopItem>()).filter {
                    !newItem.isEmpty && $0.name.lowercased().hasPrefix(newItem.lowercased())
                }
                self.filteredSuggestions = suggestions?.map { $0.name } ?? []
            }
            .onSubmit {
                // Handle submission of a new item
                guard !newItem.isEmpty else { return }
                
                let newItemName = newItem
                    .trimmingCharacters(in: .whitespacesAndNewlines) // Remove leading/trailing spaces
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) // Normalize internal spaces

                guard !newItemName.isEmpty else { return }

                // Check if item already exists
                let existingItems = try? modelContext.fetch(FetchDescriptor<ShopItem>()).filter {
                    $0.name.lowercased() == newItemName.lowercased()
                }
                guard existingItems?.isEmpty ?? true else {
                    // If item exists, reset input and suggestions
                    newItem = ""
                    filteredSuggestions = []
                    return
                }

                // Insert new item
                let item = ShopItem(name: newItemName, amount: 1, isBought: false)
                modelContext.insert(item)
                do {
                    try modelContext.save()
                } catch {
                    print("Error while saving: \(error.localizedDescription)")
                }
                newItem = ""
                filteredSuggestions = []
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
                            // Add item from suggestion
                            let existingItems = try? modelContext.fetch(FetchDescriptor<ShopItem>()).filter {
                                $0.name.lowercased() == suggestion.lowercased()
                            }
                            guard existingItems?.isEmpty ?? true else {
                                newItem = ""
                                filteredSuggestions = []
                                return
                            }
                            let item = ShopItem(name: suggestion, amount: 1, isBought: false)
                            modelContext.insert(item)
                            do {
                                try modelContext.save()
                            } catch {
                                print("Error while saving: \(error.localizedDescription)")
                            }
                            newItem = ""
                            filteredSuggestions = []
                        }
                    // Insert a divider between suggestions
                    if index < filteredSuggestions.prefix(3).count - 1 {
                        Divider()
                            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                    }
                }
            }
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width, alignment: .leading)
            .background(themedColor(darkModeColor: .black, lightModeColor: .white))
            .cornerRadius(8)
        }
    }
    
    // Utility function to return themed color based on user settings and system theme
    private func themedColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        guard let settings = settings else {
            return lightModeColor.opacity(1.0)
        }
        
        let theme = settings.themeMode
        let elementOpacity = settings.elementOpacity

        switch theme {
        case "dark":
            return darkModeColor.opacity(0.8)
        case "light":
            return lightModeColor.opacity(elementOpacity)
        case "system":
            return colorScheme == .dark
                ? darkModeColor.opacity(0.8)
                : lightModeColor.opacity(elementOpacity)
        default:
            return lightModeColor.opacity(elementOpacity)
        }
    }
}
