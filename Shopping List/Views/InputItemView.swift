//
//  InputItemView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

struct InputItemView: View {
    
    // Access the model context from the environment
    @Environment(\.modelContext) private var modelContext
    // Query to fetch items from the model that are bought
    @Query(sort: \ShopItem.name) private var items: [ShopItem]
    // Set a variable to react onto the color scheme
    @Environment(\.colorScheme) var colorScheme

    // Binding to the new item input string
    @Binding var newItem: String
    // Binding to the array of filtered suggestions based on user input
    @Binding var filteredSuggestions: [String]

    var body: some View {

        // Text input field for new shopping list items
        TextField("I need", text: $newItem)
            .padding()
            .background(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.7))
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width, maxHeight: 40)
            .font(.system(size: 18))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .cornerRadius(8)
            .padding(.horizontal)
            .onChange(of: newItem) {
                // Capitalize first letter and filter suggestions
                newItem = newItem.prefix(1).uppercased() + newItem.dropFirst()

                // Temporarily store filtered suggestions based on items in modelContext
                let suggestions = try? modelContext.fetch(FetchDescriptor<ShopItem>()).filter {
                    !newItem.isEmpty && $0.name.lowercased().hasPrefix(newItem.lowercased())
                }

                // Update filteredSuggestions Binding correctly
                self.filteredSuggestions = suggestions?.map { $0.name } ?? []
            }
            .onSubmit {
                guard !newItem.isEmpty else { return }

                let newItemName = newItem
                    .trimmingCharacters(in: .whitespacesAndNewlines) // Remove spaces leading and trailing
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) // Remove spaces inside

                guard newItemName.isEmpty == false else { return } // Just in case the text field is empty

                let existingItems = try? modelContext.fetch(FetchDescriptor<ShopItem>()).filter {
                    $0.name.lowercased() == newItemName.lowercased()
                }
                guard existingItems?.isEmpty ?? true else {
                    // Item already exists, reset input and suggestions
                    newItem = ""
                    filteredSuggestions = []
                    return
                }

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

        // Show up to 3 filtered suggestions as tappable list
        if !filteredSuggestions.isEmpty {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(filteredSuggestions.prefix(3).enumerated()), id: \.element) { index, suggestion in
                    Text(suggestion)
                        .padding(.horizontal)
                        .padding(.vertical, 9)
                        .font(.system(size: 17))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .onTapGesture {
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
                    if index < filteredSuggestions.prefix(3).count - 1 {
                        Divider()
                            .background(colorScheme == .dark ? Color.white : Color.black)
                    }
                }
            }
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width, alignment: .leading)
            .background(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.6))
            .cornerRadius(6)
        }
    }
}
