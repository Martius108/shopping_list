//
//  ShoppingListLogic.swift
//  Shopping List
//
//  Shared rules for item names, suggestions, and list ordering.
//

import Foundation

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark
}

enum ShoppingListLogic {
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
            .filter { !$0.isBought }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func recentlyBoughtItems(from items: [ShopItem], limit: Int = 30) -> [ShopItem] {
        items
            .filter(\.isBought)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }
}
