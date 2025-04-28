//
//  ShopItem.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import SwiftUI

extension Color {
    
    init(hex: String) {
        
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }

        var rgb: UInt64 = 0
        let scanner = Scanner(string: hexSanitized)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "")
        
        if scanner.scanHexInt64(&rgb) {
            let r = Double((rgb & 0xFF0000) >> 16) / 255
            let g = Double((rgb & 0x00FF00) >> 8) / 255
            let b = Double(rgb & 0x0000FF) / 255

            self.init(red: r, green: g, blue: b)
        } else {
            // If the string is invalid, fallback to white
            print("Invalid HEX string: \(hex), falling back to white color.")
            self = .white
        }
    }

    func toHex() -> String {
        
        if let components = self.cgColor?.components, components.count >= 3 {
            let r = components[0]
            let g = components[1]
            let b = components[2]

            let rValue = Int(r * 255)
            let gValue = Int(g * 255)
            let bValue = Int(b * 255)

            return String(format: "#%02X%02X%02X", rValue, gValue, bValue)
        }
        return "#FFFFFF" 
    }
}
