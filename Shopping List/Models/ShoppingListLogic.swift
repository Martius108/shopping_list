//
//  ShoppingListLogic.swift
//  Shopping List
//
//  Shared rules for item names, suggestions, and list ordering.
//

import Foundation
import CloudKit
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

    static func visibleLists(
        from lists: [ShoppingListEntry], firebaseUserID: String? = nil
    ) -> [ShoppingListEntry] {
        let accessible = lists.filter {
            $0.replacedByListID == nil && !$0.firebaseAccessRevoked
                && ($0.firebaseListID == nil
                    || (firebaseUserID != nil && $0.firebaseAccountID == firebaseUserID))
        }
        let copiedSources = Set(accessible.filter { $0.firebaseListID != nil }.compactMap(\.firebaseSourceListID))
        return accessible.filter { $0.isShared || !copiedSources.contains($0.id) }
    }

    static func isReceivedList(_ list: ShoppingListEntry, firebaseUserID: String?) -> Bool {
        if list.firebaseListID != nil { return list.firebaseOwnerID != firebaseUserID }
        return list.sharedZoneOwnerName != nil && list.sharedZoneOwnerName != CKCurrentUserDefaultName
    }

    static func otherLists(
        from lists: [ShoppingListEntry], currentID: UUID?, firebaseUserID: String?
    ) -> [ShoppingListEntry] {
        visibleLists(from: lists, firebaseUserID: firebaseUserID).filter { list in
            let shared = list.firebaseListID != nil ? list.firebaseSharingReady : list.isShared
            return list.id != currentID || (shared && !isReceivedList(list, firebaseUserID: firebaseUserID))
        }
    }

    static func sharedLists(
        from lists: [ShoppingListEntry], firebaseUserID: String?, firebaseMembers: [String: [String]]
    ) -> [ShoppingListEntry] {
        visibleLists(from: lists, firebaseUserID: firebaseUserID).filter { list in
            if let id = list.firebaseListID {
                return list.firebaseSharingReady && !(firebaseMembers[id] ?? []).isEmpty
            }
            return list.isShared
        }
    }

    static func sharingToResume(
        from lists: [ShoppingListEntry], pendingID: String, firebaseUserID: String?
    ) -> ShoppingListEntry? {
        visibleLists(from: lists, firebaseUserID: firebaseUserID).first {
            $0.id.uuidString == pendingID && !$0.firebaseSharingReady
                && !isReceivedList($0, firebaseUserID: firebaseUserID)
        }
    }

    static func listName(_ value: String) -> String? {
        let name = normalizedName(value)
        return (1...1000).contains(name.utf16.count) ? name : nil
    }

    static func firebaseCopies(
        of source: ShoppingListEntry, lists: [ShoppingListEntry], items: [ShopItem], userID: String
    ) -> [ShoppingListEntry] {
        guard source.firebaseListID == nil else { return [] }
        let sourceIDs = Set(items.filter { $0.listID == source.id }.map(\.id))
        return visibleLists(from: lists, firebaseUserID: userID).filter { copy in
            guard copy.firebaseListID != nil, copy.firebaseOwnerID == userID, !copy.isDeleted else { return false }
            if let sourceID = copy.firebaseSourceListID { return sourceID == source.id }
            // Copies made before source IDs were stored kept the original item UUIDs.
            return source.sharedZoneName != nil && !sourceIDs.isEmpty && copy.name == source.name
                && Set(items.filter { $0.listID == copy.id }.map(\.id)) == sourceIDs
        }
    }

    static func unfinishedFirebaseCopy(
        of source: ShoppingListEntry, lists: [ShoppingListEntry], items: [ShopItem], userID: String
    ) -> ShoppingListEntry? {
        let copies = firebaseCopies(of: source, lists: lists, items: items, userID: userID)
            .filter { !$0.firebaseSharingReady }
        return copies.count == 1 ? copies[0] : nil
    }

    static func emptyCloudListsMissingFromServer(
        _ lists: [ShoppingListEntry], items: [ShopItem], availableZones: Set<String>, ownerName: String,
        deletedZones: Set<String> = []
    ) -> [ShoppingListEntry] {
        let nonempty = Set(items.compactMap(\.listID))
        return lists.filter {
            guard $0.firebaseListID == nil, !$0.isShared, $0.sharedZoneOwnerName == ownerName,
                  let zone = $0.sharedZoneName else { return false }
            return (!availableZones.contains(zone) || deletedZones.contains(zone)) && !nonempty.contains($0.id)
        }
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
