import XCTest
import CloudKit
import SwiftData
@testable import Shopping_List

final class ShoppingListLogicTests: XCTestCase {
    func testDisplayNameTrimsWhitespaceAndCollapsesSpaces() {
        XCTAssertEqual(
            ShoppingListLogic.displayName(for: "  milk   chocolate  "),
            "Milk chocolate"
        )
    }

    func testMatchesIgnoresCaseAndOuterWhitespace() {
        XCTAssertTrue(ShoppingListLogic.matches(" Milk ", "milk"))
        XCTAssertTrue(ShoppingListLogic.matches("MILK", "milk"))
        XCTAssertFalse(ShoppingListLogic.matches("Milk", "Oat milk"))
    }

    func testSuggestionsAreUniqueCaseInsensitiveSortedAndLimited() {
        let suggestions = ShoppingListLogic.suggestions(
            for: "mi",
            from: ["Milk", "mineral water", "milk", "Mint", "Miso", "Oat milk", "Bread"],
            limit: 3
        )

        XCTAssertEqual(suggestions, ["Milk", "mineral water", "Mint"])
    }

    func testActiveItemsAreSortedCaseInsensitively() {
        let items = [
            ShopItem(name: "Zucchini", isBought: false),
            ShopItem(name: "Apples", isBought: false),
            ShopItem(name: "Bread", isBought: true)
        ]

        XCTAssertEqual(
            ShoppingListLogic.activeItems(from: items).map(\.name),
            ["Apples", "Zucchini"]
        )
    }

    func testRecentlyBoughtItemsAreNewestFirstAndLimited() {
        let older = ShopItem(
            name: "Older",
            isBought: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ShopItem(
            name: "Newer",
            isBought: true,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let active = ShopItem(
            name: "Active",
            isBought: false,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(
            ShoppingListLogic.recentlyBoughtItems(from: [older, newer, active], limit: 1).map(\.name),
            ["Newer"]
        )
    }

    func testDeletedItemsAreHiddenFromBothSections() {
        let deleted = ShopItem(name: "Deleted", isBought: false, deletedAt: Date())

        XCTAssertTrue(ShoppingListLogic.activeItems(from: [deleted]).isEmpty)
        XCTAssertTrue(ShoppingListLogic.recentlyBoughtItems(from: [deleted]).isEmpty)
    }

    func testVisibleItemsBelongToCurrentListOnly() {
        let personalListID = UUID()
        let sharedListID = UUID()
        let personal = ShopItem(name: "Personal", listID: personalListID)
        let shared = ShopItem(name: "Shared", listID: sharedListID, sharedZoneName: "shared-zone")

        XCTAssertEqual(
            ShoppingListLogic.visibleItems(from: [personal, shared], listID: personalListID).map(\.name),
            ["Personal"]
        )
        XCTAssertEqual(
            ShoppingListLogic.visibleItems(from: [personal, shared], listID: sharedListID).map(\.name),
            ["Shared"]
        )
    }

    func testVisibleItemsHideDuplicatePersistentObjectsWithTheSameItemID() {
        let listID = UUID()
        let itemID = UUID()
        let older = ShopItem(
            name: "Old value",
            updatedAt: Date(timeIntervalSince1970: 1),
            listID: listID
        )
        older.id = itemID
        let newer = ShopItem(
            name: "New value",
            updatedAt: Date(timeIntervalSince1970: 2),
            listID: listID
        )
        newer.id = itemID

        XCTAssertEqual(
            ShoppingListLogic.visibleItems(from: [older, newer], listID: listID).map(\.name),
            ["New value"]
        )
    }

    func testIdenticalItemIDsRemainIndependentAcrossLists() {
        let itemID = UUID()
        let firstListID = UUID()
        let secondListID = UUID()
        let first = ShopItem(name: "First", listID: firstListID)
        first.id = itemID
        let second = ShopItem(name: "Second", listID: secondListID)
        second.id = itemID

        XCTAssertEqual(
            ShoppingListLogic.visibleItems(from: [first, second], listID: firstListID).map(\.name),
            ["First"]
        )
        XCTAssertEqual(
            ShoppingListLogic.visibleItems(from: [first, second], listID: secondListID).map(\.name),
            ["Second"]
        )
    }

    func testViewSettingsDefaultsAreConsistentAndClamped() {
        let defaults = ViewSettings()
        let invalid = ViewSettings(themeMode: "neon", elementOpacity: 2)

        XCTAssertEqual(defaults.themeMode, ThemeMode.system.rawValue)
        XCTAssertEqual(defaults.backgroundColor, ViewSettings.systemBackgroundColor)
        XCTAssertEqual(defaults.elementOpacity, 1)
        XCTAssertTrue(defaults.hasMigratedDefaultAppearance)
        XCTAssertNil(defaults.currentListID)
        XCTAssertNil(defaults.sharedZoneName)
        XCTAssertNil(defaults.sharedZoneOwnerName)
        XCTAssertEqual(invalid.themeMode, ThemeMode.system.rawValue)
        XCTAssertEqual(invalid.elementOpacity, 1)
    }

    func testLegacyDefaultAppearanceMigratesOnce() {
        let settings = ViewSettings(
            backgroundColor: ViewSettings.legacyDefaultBackgroundColor,
            elementOpacity: 0.7,
            hasMigratedDefaultAppearance: false
        )

        settings.migrateDefaultAppearanceIfNeeded()

        XCTAssertEqual(settings.backgroundColor, ViewSettings.systemBackgroundColor)
        XCTAssertEqual(settings.elementOpacity, 1)
        XCTAssertTrue(settings.hasMigratedDefaultAppearance)
    }

    func testApplyingThemeRestoresSystemBackground() {
        let settings = ViewSettings(
            backgroundImageData: Data([1, 2, 3]),
            backgroundColor: "#123456"
        )

        settings.applyTheme(.dark)

        XCTAssertEqual(settings.themeMode, ThemeMode.dark.rawValue)
        XCTAssertNil(settings.backgroundImageData)
        XCTAssertEqual(settings.backgroundColor, ViewSettings.systemBackgroundColor)
    }

    func testShoppingListDefaultsToLocalList() {
        let list = ShoppingListEntry(name: "Weekly")

        XCTAssertEqual(list.name, "Weekly")
        XCTAssertNil(list.sharedZoneName)
        XCTAssertNil(list.sharedZoneOwnerName)
        XCTAssertFalse(list.isShared)
        XCTAssertNil(list.replacedByListID)
    }

    func testReplacedListsAreHidden() {
        let current = ShoppingListEntry(name: "Current")
        let duplicate = ShoppingListEntry(name: "Duplicate", replacedByListID: current.id)

        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [duplicate, current]).map(\.id), [current.id])
    }

    @MainActor
    func testEquivalentOwnedCloudListReplacesAndDeletesLocalDuplicate() throws {
        let container = try ModelContainer(
            for: ShopItem.self,
            ShoppingListEntry.self,
            ViewSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let localList = ShoppingListEntry(name: "Groceries")
        let cloudList = ShoppingListEntry(
            name: "Groceries",
            sharedZoneName: "SharedShoppingList-test",
            sharedZoneOwnerName: CKCurrentUserDefaultName
        )
        let settings = ViewSettings(currentListID: localList.id)
        let itemID = UUID()
        let localItem = ShopItem(name: "Milk", listID: localList.id)
        localItem.id = itemID
        let cloudItem = ShopItem(name: "Milk", listID: cloudList.id)
        cloudItem.id = itemID
        context.insert(localList)
        context.insert(cloudList)
        context.insert(settings)
        context.insert(localItem)
        context.insert(cloudItem)
        try context.save()

        try ShoppingListShareManager().consolidateEquivalentOwnedLists(
            lists: [localList, cloudList],
            items: [localItem, cloudItem],
            settings: settings,
            modelContext: context
        )
        try context.save()

        let savedLists = try context.fetch(FetchDescriptor<ShoppingListEntry>())
        let savedItems = try context.fetch(FetchDescriptor<ShopItem>())
        XCTAssertEqual(savedLists.map(\.id), [cloudList.id])
        XCTAssertEqual(savedItems.map(\.id), [itemID])
        XCTAssertEqual(savedItems.first?.listID, cloudList.id)
        XCTAssertEqual(settings.currentListID, cloudList.id)
    }

    @MainActor
    func testDuplicateCloudMetadataAndEmptyReplacedListAreDeleted() throws {
        let container = try ModelContainer(
            for: ShopItem.self,
            ShoppingListEntry.self,
            ViewSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let canonicalList = ShoppingListEntry(
            name: "Groceries",
            sharedZoneName: "SharedShoppingList-test",
            sharedZoneOwnerName: CKCurrentUserDefaultName
        )
        let duplicateCloudList = ShoppingListEntry(
            name: "Groceries",
            sharedZoneName: "SharedShoppingList-test",
            sharedZoneOwnerName: CKCurrentUserDefaultName
        )
        let emptyLocalList = ShoppingListEntry(
            name: "Groceries",
            replacedByListID: duplicateCloudList.id
        )
        let settings = ViewSettings(currentListID: canonicalList.id)
        let item = ShopItem(name: "Milk", listID: canonicalList.id)
        context.insert(canonicalList)
        context.insert(duplicateCloudList)
        context.insert(emptyLocalList)
        context.insert(settings)
        context.insert(item)
        try context.save()

        try ShoppingListShareManager().consolidateEquivalentOwnedLists(
            lists: [canonicalList, duplicateCloudList, emptyLocalList],
            items: [item],
            settings: settings,
            modelContext: context
        )
        try context.save()

        let savedLists = try context.fetch(FetchDescriptor<ShoppingListEntry>())
        let savedItems = try context.fetch(FetchDescriptor<ShopItem>())
        XCTAssertEqual(savedLists.map(\.id), [canonicalList.id])
        XCTAssertEqual(savedItems.map(\.id), [item.id])
        XCTAssertEqual(settings.currentListID, canonicalList.id)
    }

    @MainActor
    func testCloudSharingCancellationIsSilent() {
        XCTAssertTrue(ShoppingListShareManager.isCancellation(CancellationError()))
        XCTAssertTrue(ShoppingListShareManager.isCancellation(CKError(.operationCancelled)))
        XCTAssertFalse(ShoppingListShareManager.isCancellation(CKError(.networkFailure)))
    }

    @MainActor
    func testCloudSharingRetriesOnlyTransientFailures() {
        XCTAssertEqual(ShoppingListShareManager.retryDelay(for: CKError(.networkFailure)), 1)
        XCTAssertEqual(ShoppingListShareManager.retryDelay(for: CKError(.zoneBusy)), 1)
        XCTAssertNil(ShoppingListShareManager.retryDelay(for: CKError(.networkUnavailable)))
        XCTAssertNil(ShoppingListShareManager.retryDelay(for: CKError(.permissionFailure)))
    }

    @MainActor
    func testCloudListZoneRecognition() {
        XCTAssertTrue(ShoppingListShareManager.isShoppingListZone(
            CKRecordZone.ID(zoneName: "SharedShoppingList-example")
        ))
        XCTAssertFalse(ShoppingListShareManager.isShoppingListZone(
            CKRecordZone.ID(zoneName: "UnrelatedZone")
        ))
    }
}
