import XCTest
import CloudKit
import SwiftData
@testable import Shopping_List

final class ShoppingListLogicTests: XCTestCase {
    func testFirebaseListsAreVisibleOnlyForTheirSignedInAccount() {
        let local = ShoppingListEntry(name: "Local")
        let shared = ShoppingListEntry(name: "Shared")
        shared.firebaseListID = "remote-list"
        shared.firebaseAccountID = "alice"

        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [local, shared]).map(\.id), [local.id])
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [local, shared], firebaseUserID: "bob").map(\.id), [local.id])
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [local, shared], firebaseUserID: "alice").map(\.id), [local.id, shared.id])
    }

    func testOwnedAndReceivedListsKeepTheirRoleWhenTheSelectionChanges() {
        let own = ShoppingListEntry(name: "Private")
        let received = ShoppingListEntry(name: "Received")
        received.firebaseListID = "received"
        received.firebaseAccountID = "alice"
        received.firebaseOwnerID = "bob"
        received.firebaseSharingReady = true
        XCTAssertFalse(ShoppingListLogic.isReceivedList(own, firebaseUserID: "alice"))
        XCTAssertTrue(ShoppingListLogic.isReceivedList(received, firebaseUserID: "alice"))
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: own.id,
            firebaseUserID: "alice").map(\.id), [received.id])
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: received.id,
            firebaseUserID: "alice").map(\.id), [own.id])
    }

    func testOnlyTheOwnersSharedCurrentListAlsoAppearsUnderOtherLists() {
        let own = ShoppingListEntry(name: "Own")
        own.firebaseListID = "own"
        own.firebaseAccountID = "alice"
        own.firebaseOwnerID = "alice"
        let received = ShoppingListEntry(name: "Received")
        received.firebaseListID = "received"
        received.firebaseAccountID = "alice"
        received.firebaseOwnerID = "bob"
        received.firebaseSharingReady = true
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: own.id,
            firebaseUserID: "alice").map(\.id), [received.id])
        own.firebaseSharingReady = true
        XCTAssertFalse(ShoppingListLogic.isReceivedList(own, firebaseUserID: "alice"))
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: own.id,
            firebaseUserID: "alice").map(\.id), [own.id, received.id])
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: received.id,
            firebaseUserID: "alice").map(\.id), [own.id])
        XCTAssertTrue(ShoppingListLogic.otherLists(from: [own, received], currentID: own.id,
            firebaseUserID: "other-account").isEmpty)
    }

    func testICloudOwnershipUsesTheSameSelectedListRules() {
        let own = ShoppingListEntry(name: "Own iCloud", sharedZoneName: "own-zone",
            sharedZoneOwnerName: CKCurrentUserDefaultName, isShared: true)
        let received = ShoppingListEntry(name: "Received iCloud", sharedZoneName: "received-zone",
            sharedZoneOwnerName: "other-owner", isShared: true)
        XCTAssertFalse(ShoppingListLogic.isReceivedList(own, firebaseUserID: nil))
        XCTAssertTrue(ShoppingListLogic.isReceivedList(received, firebaseUserID: nil))
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: own.id,
            firebaseUserID: nil).map(\.id), [own.id, received.id])
        XCTAssertEqual(ShoppingListLogic.otherLists(from: [own, received], currentID: received.id,
            firebaseUserID: nil).map(\.id), [own.id])
    }

    func testFirebaseCopyReplacesOnlyItsPrivateSourceForTheSignedInAccount() {
        let source = ShoppingListEntry(name: "Private", sharedZoneName: "zone")
        let copy = ShoppingListEntry(name: "Shared")
        copy.firebaseAccountID = "alice"
        copy.firebaseSourceListID = source.id
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [source.id, copy.id])
        copy.firebaseListID = "remote"
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [copy.id])
        copy.firebaseSharingReady = true
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [copy.id])
        copy.firebaseSharingReady = false
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [copy.id])
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy]).map(\.id), [source.id])
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "bob").map(\.id), [source.id])
        source.isShared = true
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [source.id, copy.id])
        source.isShared = false
        copy.firebaseAccessRevoked = true
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [source, copy], firebaseUserID: "alice").map(\.id), [source.id])
    }

    func testSharedListsIncludeTheSameAccountOnBothPlatforms() {
        let local = ShoppingListEntry(name: "Local")
        let cloud = ShoppingListEntry(name: "iCloud", isShared: true)
        let selfOnly = ShoppingListEntry(name: "Self only")
        selfOnly.firebaseListID = "self"
        selfOnly.firebaseAccountID = "alice"
        let outgoing = ShoppingListEntry(name: "Outgoing")
        outgoing.firebaseListID = "outgoing"
        outgoing.firebaseAccountID = "alice"
        let incoming = ShoppingListEntry(name: "Incoming")
        incoming.firebaseListID = "incoming"
        incoming.firebaseAccountID = "alice"
        selfOnly.firebaseSharingReady = true
        outgoing.firebaseSharingReady = true
        incoming.firebaseSharingReady = true
        let foreign = ShoppingListEntry(name: "Other account")
        foreign.firebaseListID = "foreign"
        foreign.firebaseAccountID = "bob"
        let revoked = ShoppingListEntry(name: "Revoked")
        revoked.firebaseListID = "revoked"
        revoked.firebaseAccountID = "alice"
        revoked.firebaseAccessRevoked = true
        let replaced = ShoppingListEntry(name: "Replaced", isShared: true, replacedByListID: cloud.id)
        let all = [local, cloud, selfOnly, outgoing, incoming, foreign, revoked, replaced]
        let members = ["self": ["alice@example.test"],
                       "outgoing": ["alice@example.test", "bob@example.test"],
                       "incoming": ["carol@example.test", "alice@example.test"],
                       "foreign": ["bob@example.test", "carol@example.test"],
                       "revoked": ["alice@example.test", "bob@example.test"]]
        XCTAssertEqual(ShoppingListLogic.sharedLists(from: all, firebaseUserID: "alice", firebaseMembers: members).map(\.id),
                       [cloud.id, selfOnly.id, outgoing.id, incoming.id])
        XCTAssertEqual(ShoppingListLogic.sharedLists(from: all, firebaseUserID: nil, firebaseMembers: members).map(\.id), [cloud.id])
        XCTAssertEqual(ShoppingListLogic.sharedLists(from: all, firebaseUserID: "alice", firebaseMembers: [:]).map(\.id), [cloud.id])
        XCTAssertTrue(ShoppingListLogic.sharedLists(from: [local], firebaseUserID: "alice", firebaseMembers: members).isEmpty)
        selfOnly.firebaseSharingReady = false
        XCTAssertTrue(ShoppingListLogic.sharedLists(from: [selfOnly], firebaseUserID: "alice", firebaseMembers: members).isEmpty)
    }

    func testResumeRequiresAnExplicitOwnedUnfinishedShare() {
        let started = ShoppingListEntry(name: "Started")
        let current = ShoppingListEntry(name: "Current")
        XCTAssertEqual(ShoppingListLogic.sharingToResume(from: [started, current], pendingID: started.id.uuidString,
            firebaseUserID: "alice")?.id, started.id)
        XCTAssertEqual(ShoppingListLogic.sharingToResume(from: [started], pendingID: started.id.uuidString,
            firebaseUserID: nil)?.id, started.id)
        XCTAssertNil(ShoppingListLogic.sharingToResume(from: [current], pendingID: "", firebaseUserID: "alice"))
        started.firebaseListID = "cloud"
        started.firebaseAccountID = "alice"
        started.firebaseOwnerID = "alice"
        XCTAssertEqual(ShoppingListLogic.sharingToResume(from: [started, current], pendingID: started.id.uuidString,
            firebaseUserID: "alice")?.id, started.id)
        XCTAssertNil(ShoppingListLogic.sharingToResume(from: [started], pendingID: started.id.uuidString, firebaseUserID: "bob"))
        started.firebaseSharingReady = true
        XCTAssertNil(ShoppingListLogic.sharingToResume(from: [started], pendingID: started.id.uuidString, firebaseUserID: "alice"))
        started.firebaseSharingReady = false
        started.firebaseOwnerID = "bob"
        XCTAssertNil(ShoppingListLogic.sharingToResume(from: [started], pendingID: started.id.uuidString, firebaseUserID: "alice"))
    }

    func testLeavingTheLastReceivedListDoesNotSuggestSharingThePrivateList() {
        let own = ShoppingListEntry(name: "Own")
        XCTAssertNil(ShoppingListLogic.sharingToResume(from: [own], pendingID: "", firebaseUserID: "alice"))
        XCTAssertEqual(ShoppingListLogic.sharingToResume(from: [own], pendingID: own.id.uuidString,
            firebaseUserID: "alice")?.id, own.id)
    }

    func testListNamesAreNormalizedAndMatchTheAndroidLengthLimit() {
        XCTAssertEqual(ShoppingListLogic.listName("  Weekend   groceries "), "Weekend groceries")
        XCTAssertNil(ShoppingListLogic.listName(" \n\t "))
        XCTAssertEqual(ShoppingListLogic.listName(String(repeating: "x", count: 1000))?.count, 1000)
        XCTAssertNil(ShoppingListLogic.listName(String(repeating: "x", count: 1001)))
        XCTAssertNotNil(ShoppingListLogic.listName(String(repeating: "🍎", count: 500)))
        XCTAssertNil(ShoppingListLogic.listName(String(repeating: "🍎", count: 501)))
    }

    func testFailedUploadReusesOnlyTheUnambiguousOwnedCopy() {
        let source = ShoppingListEntry(name: "List", sharedZoneName: "zone")
        let copy = ShoppingListEntry(name: "List")
        copy.firebaseListID = "remote"
        copy.firebaseOwnerID = "alice"
        copy.firebaseAccountID = "alice"
        let item = ShopItem(name: "Milk", listID: source.id)
        let copiedItem = ShopItem(name: "Milk", listID: copy.id)
        copiedItem.id = item.id
        let all = [source, copy]
        let items = [item, copiedItem]
        XCTAssertEqual(ShoppingListLogic.unfinishedFirebaseCopy(of: source, lists: all, items: items, userID: "alice")?.id, copy.id)
        XCTAssertNil(ShoppingListLogic.unfinishedFirebaseCopy(of: source, lists: all, items: items, userID: "bob"))
        XCTAssertNil(ShoppingListLogic.unfinishedFirebaseCopy(of: source, lists: all, items: [], userID: "alice"))
        copiedItem.id = UUID()
        XCTAssertNil(ShoppingListLogic.unfinishedFirebaseCopy(of: source, lists: all, items: items, userID: "alice"))
        copiedItem.id = item.id
        copy.firebaseSharingReady = true
        XCTAssertNil(ShoppingListLogic.unfinishedFirebaseCopy(of: source, lists: all, items: items, userID: "alice"))
    }

    func testRepeatedSharingReusesCompletedCopiesAndKeepsAmbiguityVisible() {
        let source = ShoppingListEntry(name: "List", sharedZoneName: "zone")
        let copy = ShoppingListEntry(name: "List")
        copy.firebaseListID = "remote"
        copy.firebaseOwnerID = "alice"
        copy.firebaseAccountID = "alice"
        copy.firebaseSharingReady = true
        let original = ShopItem(name: "Milk", listID: source.id)
        let copied = ShopItem(name: "Milk", listID: copy.id)
        copied.id = original.id
        let items = [original, copied]
        XCTAssertEqual(ShoppingListLogic.firebaseCopies(of: source, lists: [source, copy], items: items, userID: "alice").map(\.id), [copy.id])
        XCTAssertEqual(ShoppingListLogic.firebaseCopies(of: source, lists: [source, copy], items: items, userID: "alice").map(\.id), [copy.id])
        XCTAssertTrue(ShoppingListLogic.firebaseCopies(of: source, lists: [source, copy], items: items, userID: "bob").isEmpty)
        let unrelated = ShoppingListEntry(name: "List", sharedZoneName: "other-zone")
        XCTAssertTrue(ShoppingListLogic.firebaseCopies(of: unrelated, lists: [unrelated, copy], items: items, userID: "alice").isEmpty)
        copy.firebaseSourceListID = source.id
        copy.name = "Renamed"
        XCTAssertEqual(ShoppingListLogic.firebaseCopies(of: source, lists: [source, copy], items: [], userID: "alice").map(\.id), [copy.id])
        let second = ShoppingListEntry(name: "Another copy")
        second.firebaseSourceListID = source.id
        second.firebaseListID = "second-remote"
        second.firebaseOwnerID = "alice"
        second.firebaseAccountID = "alice"
        XCTAssertEqual(ShoppingListLogic.firebaseCopies(of: source, lists: [source, copy, second], items: [], userID: "alice").count, 2)
    }

    func testMissingCloudZoneRemovesOnlyEmptyOwnedPrivateEntries() {
        let obsolete = ShoppingListEntry(name: "Deleted", sharedZoneName: "gone", sharedZoneOwnerName: "owner")
        let available = ShoppingListEntry(name: "Existing", sharedZoneName: "present", sharedZoneOwnerName: "owner")
        let dirty = ShoppingListEntry(name: "Offline edits", sharedZoneName: "offline", sharedZoneOwnerName: "owner")
        let guest = ShoppingListEntry(name: "Received", sharedZoneName: "guest", sharedZoneOwnerName: "other")
        let shared = ShoppingListEntry(name: "Shared", sharedZoneName: "shared", sharedZoneOwnerName: "owner", isShared: true)
        let firebase = ShoppingListEntry(name: "Firebase", sharedZoneName: "legacy", sharedZoneOwnerName: "owner")
        firebase.firebaseListID = "remote"
        let local = ShoppingListEntry(name: "New private")
        let item = ShopItem(name: "Unsaved milk", listID: dirty.id)
        XCTAssertEqual(ShoppingListLogic.emptyCloudListsMissingFromServer(
            [obsolete, available, dirty, guest, shared, firebase, local], items: [item],
            availableZones: ["present"], ownerName: "owner").map(\.id), [obsolete.id])
        XCTAssertEqual(ShoppingListLogic.emptyCloudListsMissingFromServer(
            [obsolete, available, dirty, guest, shared, firebase, local], items: [item],
            availableZones: ["gone", "present", "offline"], ownerName: "owner",
            deletedZones: ["gone", "offline"]).map(\.id), [obsolete.id])
    }

    func testRevokedFirebaseListIsHiddenUntilAccessIsRestored() {
        let list = ShoppingListEntry(name: "Shared")
        list.firebaseListID = "remote-list"
        list.firebaseAccountID = "alice"
        list.firebaseAccessRevoked = true
        XCTAssertTrue(ShoppingListLogic.visibleLists(from: [list], firebaseUserID: "alice").isEmpty)
        list.firebaseAccessRevoked = false
        XCTAssertEqual(ShoppingListLogic.visibleLists(from: [list], firebaseUserID: "alice").map(\.id), [list.id])
    }

    @MainActor
    func testFirebaseCopyIsNotMergedBackIntoItsICloudSource() throws {
        let container = try ModelContainer(
            for: ShopItem.self, ShoppingListEntry.self, ViewSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let cloud = ShoppingListEntry(name: "Groceries", sharedZoneName: "SharedShoppingList-test",
                                      sharedZoneOwnerName: CKCurrentUserDefaultName)
        let firebase = ShoppingListEntry(name: "Groceries")
        firebase.firebaseListID = "firebase-list"
        firebase.firebaseAccountID = "alice"
        let original = ShopItem(name: "Milk", listID: cloud.id)
        let copy = ShopItem(name: "Milk", listID: firebase.id)
        copy.id = original.id
        context.insert(cloud)
        context.insert(firebase)
        context.insert(original)
        context.insert(copy)
        try context.save()
        try ShoppingListShareManager().consolidateEquivalentOwnedLists(
            lists: [cloud, firebase], items: [original, copy], settings: ViewSettings(), modelContext: context
        )
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShoppingListEntry>()), 2)
        XCTAssertEqual(copy.listID, firebase.id)
        XCTAssertEqual(firebase.firebaseListID, "firebase-list")
    }

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
