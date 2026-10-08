//
//  ShopItem.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import Foundation
import SwiftData

@Model
// Model class holding the data for shop the list items
final class ShopItem: Identifiable {

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var amount: Int = 1
    var isBought: Bool = false
    var listID: UUID?
    var sharedZoneName: String?

    init(
        name: String,
        amount: Int = 1,
        isBought: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        listID: UUID? = nil,
        sharedZoneName: String? = nil
    ) {

        self.name = name
        self.amount = amount
        self.isBought = isBought
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.listID = listID
        self.sharedZoneName = sharedZoneName
    }
}
