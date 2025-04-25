//
//  ShopItem.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import Foundation
import SwiftData

@Model
class ShopItem: Identifiable {
    
    var id: UUID = UUID()
    var name: String
    var amount: Int = 1
    
    init(name: String, amount: Int = 1) {
        self.name = name
        self.amount = amount
    }
}
