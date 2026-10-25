import Foundation
import SwiftData

@Model
final class ShoppingListEntry: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sharedZoneName: String?
    var sharedZoneOwnerName: String?
    var isShared: Bool = false
    var replacedByListID: UUID?
    var firebaseSourceListID: UUID?
    var firebaseListID: String?
    var firebaseOwnerID: String?
    var firebaseAccountID: String?
    var firebaseAccessRevoked: Bool = false
    var firebaseSharingReady: Bool = false

    init(
        name: String,
        createdAt: Date = Date(),
        sharedZoneName: String? = nil,
        sharedZoneOwnerName: String? = nil,
        isShared: Bool = false,
        replacedByListID: UUID? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.sharedZoneName = sharedZoneName
        self.sharedZoneOwnerName = sharedZoneOwnerName
        self.isShared = isShared
        self.replacedByListID = replacedByListID
    }
}
