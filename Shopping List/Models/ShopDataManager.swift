//
//  ShopData.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import Foundation
import SwiftData

class ShopDataManager: ObservableObject {

    // All known items, both active and bought
    @Published var itemsList: [ShopItem] = []
    
    // Items currently on the shopping list (to be bought)
    @Published var currentItemsList: [ShopItem] = []
    
    // Items that have been marked as bought
    @Published var boughtItemsList: [ShopItem] = []

    init() {}
    
    // Returns a sorted array of unique item names from the entire list
    var allItemNames: [String] {
        return Array(Set(itemsList.map { $0.name })).sorted()
    }

    // Adds a new item to the current shopping list or reactivates it if already known
    func appendItem(name: String, context: ModelContext) {
        // Ignore empty input
        guard !name.isEmpty else { return }

        // Reactivate item from bought list if it matches
        let cleanInput = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let index = boughtItemsList.firstIndex(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanInput
        }) {
            let item = boughtItemsList.remove(at: index)
            currentItemsList.append(item)
            return
        }

        // Prevent duplicates in current list
        if currentItemsList.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return
        }

        // Reuse from known items if it exists
        if let existingItem = itemsList.first(where: { $0.name.lowercased() == name.lowercased() }) {
            currentItemsList.append(existingItem)
            return
        }

        // Create a completely new item
        let newItem = ShopItem(name: name)
        context.insert(newItem)

        currentItemsList.append(newItem)
        // Force view update in case it's the first item
        currentItemsList = currentItemsList

        if !itemsList.contains(where: { $0.name.lowercased() == newItem.name.lowercased() }) {
            itemsList.append(newItem)
        }
    }

    // Moves an item from the current list to the bought list
    func markItemAsBought(item: ShopItem, context: ModelContext) {
        if let index = currentItemsList.firstIndex(where: { $0.id == item.id }) {
            let boughtItem = currentItemsList.remove(at: index)
            boughtItemsList.insert(boughtItem, at: 0)
            context.insert(boughtItem)
        }
    }
    
    // Moves an item from the bought list back to the current list
    func reactivateItem(_ item: ShopItem) {
        if let index = boughtItemsList.firstIndex(where: { $0.id == item.id }) {
            let itemToMove = boughtItemsList.remove(at: index)
            currentItemsList.append(itemToMove)
        }
    }
    
    // Updates the quantity of a given item
    func updateItemAmount(item: ShopItem, amount: Int, context: ModelContext) {
        item.amount = amount
        context.insert(item)
    }
}
    
