import CloudKit
import SwiftData
import SwiftUI

extension Notification.Name {
    static let shoppingListShareAccepted = Notification.Name("shoppingListShareAccepted")
}

@MainActor
final class ShoppingListShareManager: ObservableObject {
    static let containerIdentifier = "iCloud.com.martinlanius.Shopping-List"

    private enum Field {
        static let name = "name"
        static let amount = "amount"
        static let isBought = "isBought"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let deletedAt = "deletedAt"
    }

    private struct ZoneIdentity: Hashable {
        let name: String
        let ownerName: String?
    }

    private static let itemRecordType = "ShoppingListItem"
    private static let zoneNamePrefix = "SharedShoppingList-"
    private static let pendingZoneNameKey = "pendingSharedShoppingListZoneName"
    private static let pendingOwnerNameKey = "pendingSharedShoppingListOwnerName"
    private static let pendingTitleKey = "pendingSharedShoppingListTitle"

    let container = CKContainer(identifier: containerIdentifier)

    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published private(set) var share: CKShare?
    @Published private(set) var activeListID: UUID?
    @Published private(set) var isWorking = false
    @Published private(set) var isSyncing = false
    @Published private(set) var alertMessage: String?

    private var syncingListIDs = Set<UUID>()
    private var syncAgainListIDs = Set<UUID>()
    private var isRestoringLists = false

    var acceptedParticipantCount: Int {
        share?.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }.count ?? 0
    }

    var pendingParticipantCount: Int {
        share?.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .pending
        }.count ?? 0
    }

    var currentRole: CKShare.ParticipantRole? {
        share?.currentUserParticipant?.role
    }

    var currentPermission: CKShare.ParticipantPermission? {
        share?.currentUserParticipant?.permission
    }

    static func storeAcceptedShare(_ share: CKShare) {
        let defaults = UserDefaults.standard
        defaults.set(share.recordID.zoneID.zoneName, forKey: pendingZoneNameKey)
        defaults.set(share.recordID.zoneID.ownerName, forKey: pendingOwnerNameKey)
        defaults.set(share[CKShare.SystemFieldKey.title] as? String, forKey: pendingTitleKey)
        NotificationCenter.default.post(name: .shoppingListShareAccepted, object: nil)
    }

    func refresh(list: ShoppingListEntry) async {
        let listID = list.id
        if activeListID != listID {
            activeListID = listID
            share = nil
        }

        do {
            let fetchedShare = try await retryingOnce { () async throws -> CKShare? in
                self.accountStatus = try await self.container.accountStatus()
                guard let zoneID = self.zoneID(for: list) else { return nil }
                return try await self.fetchShare(in: zoneID)
            }
            guard activeListID == listID else { return }
            share = fetchedShare
            list.isShared = sharingIsActive(fetchedShare, zoneID: zoneID(for: list))
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            if activeListID == listID {
                share = nil
            }
            list.isShared = false
        } catch {
            print("Could not refresh CloudKit sharing: \(error.localizedDescription)")
        }
    }

    func consumeAcceptedShare(
        settings: ViewSettings,
        modelContext: ModelContext
    ) async -> UUID? {
        let defaults = UserDefaults.standard
        guard
            let zoneName = defaults.string(forKey: Self.pendingZoneNameKey),
            let ownerName = defaults.string(forKey: Self.pendingOwnerNameKey)
        else { return nil }

        do {
            let lists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
            let list: ShoppingListEntry
            if let existingList = lists.first(where: {
                $0.sharedZoneName == zoneName && $0.sharedZoneOwnerName == ownerName
            }) {
                list = existingList
                list.isShared = true
            } else {
                list = ShoppingListEntry(
                    name: defaults.string(forKey: Self.pendingTitleKey)
                        ?? String(localized: "Shared Shopping List"),
                    sharedZoneName: zoneName,
                    sharedZoneOwnerName: ownerName,
                    isShared: true
                )
                modelContext.insert(list)
            }
            settings.currentListID = list.id
            try modelContext.save()

            defaults.removeObject(forKey: Self.pendingZoneNameKey)
            defaults.removeObject(forKey: Self.pendingOwnerNameKey)
            defaults.removeObject(forKey: Self.pendingTitleKey)
            await refresh(list: list)
            await sync(list: list, modelContext: modelContext)
            return list.id
        } catch {
            print("Could not store accepted CloudKit share: \(error.localizedDescription)")
            return nil
        }
    }

    func restoreCloudLists(settings: ViewSettings, modelContext: ModelContext) async {
        guard !isRestoringLists else { return }
        isRestoringLists = true
        defer { isRestoringLists = false }

        do {
            var lists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
            let items = try modelContext.fetch(FetchDescriptor<ShopItem>())
            try consolidateEquivalentOwnedLists(
                lists: lists,
                items: items,
                settings: settings,
                modelContext: modelContext
            )
            try modelContext.save()

            accountStatus = try await container.accountStatus()
            guard accountStatus == .available else { return }

            let privateZones = try await container.privateCloudDatabase.allRecordZones()
            let sharedZones = try await container.sharedCloudDatabase.allRecordZones()
            let cloudZoneIDs = (privateZones + sharedZones)
                .map(\.zoneID)
                .filter(Self.isShoppingListZone)

            lists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
            var reusableList = lists.count == 1
                && lists[0].sharedZoneName == nil
                && lists[0].name == String(localized: "Shopping List")
                ? lists[0]
                : nil
            var restoredLists: [ShoppingListEntry] = []

            for zoneID in cloudZoneIDs {
                let cloudShare = try await fetchShare(in: zoneID)
                if let existingList = lists.first(where: {
                    $0.sharedZoneName == zoneID.zoneName
                        && $0.sharedZoneOwnerName == zoneID.ownerName
                }) {
                    existingList.isShared = sharingIsActive(cloudShare, zoneID: zoneID)
                    continue
                }
                let title = cloudShare?[CKShare.SystemFieldKey.title] as? String
                    ?? String(localized: "Shopping List")
                let list: ShoppingListEntry

                if zoneID.ownerName == CKCurrentUserDefaultName,
                   let existingReusableList = reusableList {
                    existingReusableList.name = title
                    existingReusableList.sharedZoneName = zoneID.zoneName
                    existingReusableList.sharedZoneOwnerName = zoneID.ownerName
                    existingReusableList.isShared = sharingIsActive(cloudShare, zoneID: zoneID)
                    list = existingReusableList
                    reusableList = nil
                } else {
                    list = ShoppingListEntry(
                        name: title,
                        sharedZoneName: zoneID.zoneName,
                        sharedZoneOwnerName: zoneID.ownerName,
                        isShared: sharingIsActive(cloudShare, zoneID: zoneID)
                    )
                    modelContext.insert(list)
                    lists.append(list)
                }
                restoredLists.append(list)
            }

            try consolidateEquivalentOwnedLists(
                lists: lists,
                items: items,
                settings: settings,
                modelContext: modelContext
            )
            guard !restoredLists.isEmpty else {
                try modelContext.save()
                return
            }
            if settings.currentListID == nil || lists.count == restoredLists.count {
                settings.currentListID = restoredLists[0].id
            }
            try modelContext.save()

            for list in restoredLists {
                await sync(list: list, modelContext: modelContext)
            }
        } catch {
            print("Could not restore CloudKit shopping lists: \(error.localizedDescription)")
        }
    }

    func consolidateEquivalentOwnedLists(
        lists: [ShoppingListEntry],
        items: [ShopItem],
        settings: ViewSettings,
        modelContext: ModelContext
    ) throws {
        ShoppingListLogic.removeDuplicateItems(from: items, modelContext: modelContext)

        let itemCounts = Dictionary(grouping: items.compactMap { item in
            item.listID.map { ($0, item.id) }
        }, by: \.0).mapValues { Set($0.map(\.1)).count }
        let cloudListGroups = Dictionary(grouping: lists.compactMap { list in
            list.sharedZoneName.map {
                (ZoneIdentity(name: $0, ownerName: list.sharedZoneOwnerName), list)
            }
        }, by: \.0)

        for group in cloudListGroups.values.map({ $0.map(\.1) }) where group.count > 1 {
            guard let canonicalList = group.max(by: { lhs, rhs in
                let lhsCount = itemCounts[lhs.id] ?? 0
                let rhsCount = itemCounts[rhs.id] ?? 0
                if lhsCount != rhsCount { return lhsCount < rhsCount }

                let lhsIsCurrent = lhs.id == settings.currentListID
                let rhsIsCurrent = rhs.id == settings.currentListID
                if lhsIsCurrent != rhsIsCurrent { return !lhsIsCurrent && rhsIsCurrent }
                return lhs.createdAt > rhs.createdAt
            }) else { continue }

            for duplicateList in group where duplicateList !== canonicalList {
                if settings.currentListID == duplicateList.id {
                    settings.currentListID = canonicalList.id
                }
                for list in lists where list.replacedByListID == duplicateList.id {
                    list.replacedByListID = canonicalList.id
                }
                merge(
                    duplicateList,
                    into: canonicalList,
                    items: items,
                    modelContext: modelContext
                )
            }
        }

        let remainingLists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
        let remainingItems = try modelContext.fetch(FetchDescriptor<ShopItem>())
        let itemIDsByList = Dictionary(grouping: remainingItems.compactMap { item in
            item.listID.map { ($0, item.id) }
        }, by: \.0).mapValues { Set($0.map(\.1)) }

        let ownedCloudLists = remainingLists.filter {
            $0.sharedZoneOwnerName == CKCurrentUserDefaultName
        }

        for localList in remainingLists where localList.sharedZoneName == nil {
            let localItemIDs = itemIDsByList[localList.id] ?? []
            if localItemIDs.isEmpty,
               let replacementID = localList.replacedByListID,
               let replacement = ownedCloudLists.first(where: { $0.id == replacementID }) {
                if settings.currentListID == localList.id {
                    settings.currentListID = replacement.id
                }
                modelContext.delete(localList)
                continue
            }
            guard !localItemIDs.isEmpty else { continue }
            let cloudList: ShoppingListEntry?
            if let replacementID = localList.replacedByListID {
                cloudList = ownedCloudLists.first {
                    $0.id == replacementID && itemIDsByList[$0.id] == localItemIDs
                }
            } else {
                cloudList = ownedCloudLists.first {
                    ShoppingListLogic.matches($0.name, localList.name)
                        && itemIDsByList[$0.id] == localItemIDs
                }
            }
            guard let cloudList else {
                localList.replacedByListID = nil
                continue
            }

            if settings.currentListID == localList.id {
                settings.currentListID = cloudList.id
            }
            merge(localList, into: cloudList, items: remainingItems, modelContext: modelContext)
        }
    }

    private func merge(
        _ duplicateList: ShoppingListEntry,
        into canonicalList: ShoppingListEntry,
        items: [ShopItem],
        modelContext: ModelContext
    ) {
        let canonicalItems = ShoppingListLogic.uniqueItems(
            from: items.filter { $0.listID == canonicalList.id }
        )
        let canonicalByID = Dictionary(uniqueKeysWithValues: canonicalItems.map { ($0.id, $0) })
        let duplicateItems = ShoppingListLogic.uniqueItems(
            from: items.filter { $0.listID == duplicateList.id }
        )

        for duplicateItem in duplicateItems {
            if let canonicalItem = canonicalByID[duplicateItem.id] {
                if duplicateItem.updatedAt > canonicalItem.updatedAt {
                    canonicalItem.name = duplicateItem.name
                    canonicalItem.amount = duplicateItem.amount
                    canonicalItem.isBought = duplicateItem.isBought
                    canonicalItem.createdAt = duplicateItem.createdAt
                    canonicalItem.updatedAt = duplicateItem.updatedAt
                    canonicalItem.deletedAt = duplicateItem.deletedAt
                }
                modelContext.delete(duplicateItem)
            } else {
                duplicateItem.listID = canonicalList.id
                duplicateItem.sharedZoneName = canonicalList.sharedZoneName
            }
        }
        modelContext.delete(duplicateList)
    }

    func prepareShare(list: ShoppingListEntry, modelContext: ModelContext) async -> CKShare? {
        guard !isWorking else { return nil }
        activeListID = list.id
        isWorking = true
        alertMessage = nil
        defer { isWorking = false }

        do {
            return try await retryingOnce {
                try await prepareShareAttempt(list: list, modelContext: modelContext)
            }
        } catch {
            if !Self.isCancellation(error) {
                updateAccountStatus(for: error)
                alertMessage = Self.alertMessage(for: error)
                print("Could not prepare CloudKit sharing: \(error.localizedDescription)")
            }
            return nil
        }
    }

    func stopSharing(
        list: ShoppingListEntry,
        settings: ViewSettings,
        modelContext: ModelContext
    ) async -> Bool {
        guard !isWorking, let zoneID = zoneID(for: list) else { return false }
        isWorking = true
        alertMessage = nil
        defer { isWorking = false }

        do {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            try await retryingOnce {
                do {
                    _ = try await self.database(for: zoneID).deleteRecord(withID: shareID)
                } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                    return
                }
            }

            if zoneID.ownerName == CKCurrentUserDefaultName {
                list.isShared = false
                try modelContext.save()
            } else {
                try removeLocalList(list, settings: settings, modelContext: modelContext)
            }
            if activeListID == list.id {
                share = nil
            }
            return true
        } catch {
            modelContext.rollback()
            handleActionError(error, context: "stop sharing")
            return false
        }
    }

    func deleteList(
        _ list: ShoppingListEntry,
        settings: ViewSettings,
        modelContext: ModelContext
    ) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        alertMessage = nil
        defer { isWorking = false }

        do {
            if let zoneID = zoneID(for: list) {
                try await retryingOnce {
                    do {
                        if zoneID.ownerName == CKCurrentUserDefaultName {
                            _ = try await self.container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
                        } else {
                            let shareID = CKRecord.ID(
                                recordName: CKRecordNameZoneWideShare,
                                zoneID: zoneID
                            )
                            _ = try await self.container.sharedCloudDatabase.deleteRecord(withID: shareID)
                        }
                    } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                        return
                    }
                }
            }

            try removeLocalList(list, settings: settings, modelContext: modelContext)
            if activeListID == list.id {
                activeListID = nil
                share = nil
            }
            return true
        } catch {
            modelContext.rollback()
            handleActionError(error, context: "delete list")
            return false
        }
    }

    func sync(list: ShoppingListEntry, modelContext: ModelContext) async {
        guard zoneID(for: list) != nil else { return }
        let listID = list.id
        guard !syncingListIDs.contains(listID) else {
            syncAgainListIDs.insert(listID)
            return
        }

        syncingListIDs.insert(listID)
        isSyncing = !syncingListIDs.isEmpty
        repeat {
            syncAgainListIDs.remove(listID)
            do {
                try await retryingOnce {
                    try await performSync(list: list, modelContext: modelContext)
                }
            } catch {
                print("Could not sync shared shopping list: \(error.localizedDescription)")
            }
        } while syncAgainListIDs.contains(listID)
        syncingListIDs.remove(listID)
        isSyncing = !syncingListIDs.isEmpty
    }

    func dismissAlert() {
        alertMessage = nil
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? CKError)?.code == .operationCancelled
    }

    static func retryDelay(for error: Error) -> TimeInterval? {
        guard let error = error as? CKError else { return nil }

        switch error.code {
        case .networkFailure, .serverResponseLost:
            return 1
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let delay = (error.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue ?? 1
            return delay <= 5 ? max(delay, 0.1) : nil
        default:
            return nil
        }
    }

    static func isShoppingListZone(_ zoneID: CKRecordZone.ID) -> Bool {
        zoneID.zoneName.hasPrefix(zoneNamePrefix)
    }

    private func prepareShareAttempt(
        list: ShoppingListEntry,
        modelContext: ModelContext
    ) async throws -> CKShare {
        accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw CKError(.notAuthenticated)
        }

        let zoneID = try await ensureZone(list: list, modelContext: modelContext)
        if let existingShare = try await fetchShare(in: zoneID) {
            list.isShared = sharingIsActive(existingShare, zoneID: zoneID)
            share = existingShare
            return existingShare
        }

        try await performSync(list: list, modelContext: modelContext)

        let newShare = CKShare(recordZoneID: zoneID)
        newShare[CKShare.SystemFieldKey.title] = list.name
        newShare.publicPermission = .none
        let savedShare = try await container.privateCloudDatabase.save(newShare)
        guard let savedShare = savedShare as? CKShare else {
            throw CKError(.internalError)
        }
        list.isShared = false
        share = savedShare
        return savedShare
    }

    private func retryingOnce<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard let delay = Self.retryDelay(for: error) else { throw error }
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return try await operation()
        }
    }

    private func removeLocalList(
        _ list: ShoppingListEntry,
        settings: ViewSettings,
        modelContext: ModelContext
    ) throws {
        let allLists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
        let targetIDs = Set(allLists.compactMap { candidate in
            candidate.id == list.id || candidate.replacedByListID == list.id
                ? candidate.id
                : nil
        })
        let allItems = try modelContext.fetch(FetchDescriptor<ShopItem>())

        for item in allItems where item.listID.map(targetIDs.contains) == true {
            modelContext.delete(item)
        }
        for candidate in allLists where targetIDs.contains(candidate.id) {
            modelContext.delete(candidate)
        }

        let remainingLists = ShoppingListLogic.visibleLists(
            from: allLists.filter { !targetIDs.contains($0.id) }
        )
        if targetIDs.contains(settings.currentListID ?? UUID()) {
            if let replacement = remainingLists.first {
                settings.currentListID = replacement.id
            } else {
                let replacement = ShoppingListEntry(name: String(localized: "Shopping List"))
                modelContext.insert(replacement)
                settings.currentListID = replacement.id
            }
        }
        try modelContext.save()
    }

    private func handleActionError(_ error: Error, context: String) {
        guard !Self.isCancellation(error) else { return }
        updateAccountStatus(for: error)
        alertMessage = Self.alertMessage(for: error)
        print("Could not \(context): \(error.localizedDescription)")
    }

    private func updateAccountStatus(for error: Error) {
        guard let error = error as? CKError else { return }

        switch error.code {
        case .notAuthenticated:
            accountStatus = .noAccount
        case .managedAccountRestricted:
            accountStatus = .restricted
        case .accountTemporarilyUnavailable:
            accountStatus = .temporarilyUnavailable
        default:
            break
        }
    }

    private func sharingIsActive(_ share: CKShare?, zoneID: CKRecordZone.ID?) -> Bool {
        guard let zoneID else { return false }
        if zoneID.ownerName != CKCurrentUserDefaultName {
            return true
        }
        return share?.participants.contains {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        } ?? false
    }

    private static func alertMessage(for error: Error) -> String {
        guard let error = error as? CKError else {
            return String(localized: "iCloud sharing could not be completed. Please try again.")
        }

        switch error.code {
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud in Settings and try again.")
        case .networkUnavailable, .networkFailure:
            return String(localized: "Check your internet connection and try again.")
        case .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .serverResponseLost, .accountTemporarilyUnavailable:
            return String(localized: "iCloud is temporarily unavailable. Please try again later.")
        case .quotaExceeded:
            return String(localized: "There is not enough iCloud storage for sharing.")
        case .permissionFailure, .managedAccountRestricted:
            return String(localized: "Sharing is not available for this iCloud account.")
        default:
            return String(localized: "iCloud sharing could not be completed. Please try again.")
        }
    }

    private func ensureZone(list: ShoppingListEntry, modelContext: ModelContext) async throws -> CKRecordZone.ID {
        if let zoneID = zoneID(for: list) {
            if zoneID.ownerName == CKCurrentUserDefaultName {
                _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
            }
            return zoneID
        }

        let zoneID = CKRecordZone.ID(zoneName: "\(Self.zoneNamePrefix)\(UUID().uuidString)")
        list.sharedZoneName = zoneID.zoneName
        list.sharedZoneOwnerName = zoneID.ownerName
        _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))

        let items = try modelContext.fetch(FetchDescriptor<ShopItem>())
        for item in items where item.listID == list.id {
            item.sharedZoneName = zoneID.zoneName
            item.updatedAt = Date()
        }
        try modelContext.save()
        return zoneID
    }

    private func performSync(list: ShoppingListEntry, modelContext: ModelContext) async throws {
        guard let zoneID = zoneID(for: list) else { return }
        let database = database(for: zoneID)
        let remoteRecords = try await fetchItemRecords(from: database, zoneID: zoneID)
        let allLocalItems = try modelContext.fetch(FetchDescriptor<ShopItem>())
        ShoppingListLogic.removeDuplicateItems(from: allLocalItems, modelContext: modelContext)
        let localItems = ShoppingListLogic.uniqueItems(
            from: allLocalItems.filter { $0.listID == list.id }
        )
        var localByID = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })
        var remoteIDs = Set<UUID>()

        for record in remoteRecords {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            remoteIDs.insert(id)
            if let localItem = localByID[id] {
                let remoteUpdatedAt = record[Field.updatedAt] as? Date ?? .distantPast
                if remoteUpdatedAt > localItem.updatedAt {
                    apply(record, to: localItem, list: list)
                } else if localItem.updatedAt > remoteUpdatedAt {
                    _ = try await database.save(cloudRecord(for: localItem, in: zoneID, existing: record))
                }
            } else if let item = item(from: record, list: list) {
                modelContext.insert(item)
                localByID[id] = item
            }
        }

        for item in localItems where !remoteIDs.contains(item.id) {
            _ = try await database.save(cloudRecord(for: item, in: zoneID))
        }

        try modelContext.save()
    }

    private func fetchShare(in zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let recordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await database(for: zoneID).record(for: recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func fetchItemRecords(from database: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var changeToken: CKServerChangeToken?
        var moreComing = false

        repeat {
            let response = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )
            for result in response.modificationResultsByID.values {
                let modification = try result.get()
                if modification.record.recordType == Self.itemRecordType {
                    records.append(modification.record)
                }
            }
            changeToken = response.changeToken
            moreComing = response.moreComing
        } while moreComing

        return records
    }

    private func database(for zoneID: CKRecordZone.ID) -> CKDatabase {
        zoneID.ownerName == CKCurrentUserDefaultName
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase
    }

    private func zoneID(for list: ShoppingListEntry) -> CKRecordZone.ID? {
        guard
            let zoneName = list.sharedZoneName,
            let ownerName = list.sharedZoneOwnerName
        else { return nil }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    private func cloudRecord(for item: ShopItem, in zoneID: CKRecordZone.ID, existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: Self.itemRecordType,
            recordID: CKRecord.ID(recordName: item.id.uuidString, zoneID: zoneID)
        )
        record[Field.name] = item.name
        record[Field.amount] = Int64(item.amount)
        record[Field.isBought] = item.isBought ? Int64(1) : Int64(0)
        record[Field.createdAt] = item.createdAt
        record[Field.updatedAt] = item.updatedAt
        record[Field.deletedAt] = item.deletedAt
        return record
    }

    private func item(from record: CKRecord, list: ShoppingListEntry) -> ShopItem? {
        guard
            let id = UUID(uuidString: record.recordID.recordName),
            let name = record[Field.name] as? String
        else { return nil }

        let item = ShopItem(
            name: name,
            amount: max(Int(record[Field.amount] as? Int64 ?? 1), 1),
            isBought: (record[Field.isBought] as? Int64 ?? 0) != 0,
            createdAt: record[Field.createdAt] as? Date ?? Date(),
            updatedAt: record[Field.updatedAt] as? Date ?? Date(),
            deletedAt: record[Field.deletedAt] as? Date,
            listID: list.id,
            sharedZoneName: list.sharedZoneName
        )
        item.id = id
        return item
    }

    private func apply(_ record: CKRecord, to item: ShopItem, list: ShoppingListEntry) {
        guard let name = record[Field.name] as? String else { return }
        item.name = name
        item.amount = max(Int(record[Field.amount] as? Int64 ?? 1), 1)
        item.isBought = (record[Field.isBought] as? Int64 ?? 0) != 0
        item.createdAt = record[Field.createdAt] as? Date ?? item.createdAt
        item.updatedAt = record[Field.updatedAt] as? Date ?? item.updatedAt
        item.deletedAt = record[Field.deletedAt] as? Date
        item.listID = list.id
        item.sharedZoneName = list.sharedZoneName
    }
}
