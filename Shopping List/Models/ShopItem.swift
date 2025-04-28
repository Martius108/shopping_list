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
class ShopItem {

    var name: String = ""
    var amount: Int = 1
    var isBought: Bool = false

    init(name: String, amount: Int = 1, isBought: Bool = false) {

        self.name = name
        self.amount = amount
        self.isBought = isBought
    }
}
