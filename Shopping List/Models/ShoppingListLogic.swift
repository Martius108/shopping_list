//
//  ShoppingListLogic.swift
//  Shopping List
//
//  Shared rules for item names, suggestions, and list ordering.
//

import Foundation
import SwiftData

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark
}

enum ShoppingListLogic {
    private struct ItemIdentity: Hashable {
        let listID: UUID?
        let itemID: UUID
    }

    static func visibleLists(from lists: [ShoppingListEntry]) -> [ShoppingListEntry] {
        lists.filter { $0.replacedByListID == nil }
    }

    static func visibleItems(from items: [ShopItem], listID: UUID) -> [ShopItem] {
        uniqueItems(from: items.filter { $0.listID == listID })
    }

    static func uniqueItems(from items: [ShopItem]) -> [ShopItem] {
        Dictionary(grouping: items) {
            ItemIdentity(listID: $0.listID, itemID: $0.id)
        }
        .values
        .compactMap(preferredItem)
    }

    @discardableResult
    static func removeDuplicateItems(
        from items: [ShopItem],
        modelContext: ModelContext
    ) -> Int {
        var removedCount = 0
        let groups = Dictionary(grouping: items) {
            ItemIdentity(listID: $0.listID, itemID: $0.id)
        }

        for group in groups.values where group.count > 1 {
            guard let preferred = preferredItem(in: group) else { continue }
            for duplicate in group where duplicate !== preferred {
                modelContext.delete(duplicate)
                removedCount += 1
            }
        }
        return removedCount
    }

    private static func preferredItem(in items: [ShopItem]) -> ShopItem? {
        items.max {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.createdAt < $1.createdAt
        }
    }

    static func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    static func displayName(for value: String) -> String {
        let normalized = normalizedName(value)
        guard let first = normalized.first else { return "" }
        return first.uppercased() + normalized.dropFirst()
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalizedName(lhs).localizedCaseInsensitiveCompare(normalizedName(rhs)) == .orderedSame
    }

    static func suggestions(for input: String, from itemNames: [String], limit: Int = 3) -> [String] {
        let query = normalizedName(input)
        guard !query.isEmpty else { return [] }

        var seen = Set<String>()
        return itemNames
            .filter {
                normalizedName($0).range(
                    of: query,
                    options: [.caseInsensitive, .anchored, .diacriticInsensitive],
                    locale: .current
                ) != nil
            }
            .compactMap { name in
                let normalized = normalizedName(name)
                let key = normalized.lowercased()
                guard !normalized.isEmpty, !seen.contains(key) else { return nil }
                seen.insert(key)
                return normalized
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }

    static func activeItems(from items: [ShopItem]) -> [ShopItem] {
        items
            .filter { !$0.isBought && $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func recentlyBoughtItems(from items: [ShopItem], limit: Int = 30) -> [ShopItem] {
        items
            .filter { $0.isBought && $0.deletedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
}
