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
    var amount: Int = 1
    var isBought: Bool = false

    init(name: String, createdAt: Date = Date(), amount: Int = 1, isBought: Bool = false) {

        self.name = name
        self.createdAt = createdAt
        self.amount = amount
        self.isBought = isBought
    }
}
