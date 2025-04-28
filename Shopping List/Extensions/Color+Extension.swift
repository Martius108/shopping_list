//
//  Color+Extension.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import SwiftUI

// Extension to create a Color from a hex string and to convert a Color back to a hex string
extension Color {
    
    // Initializes a Color instance from a hexadecimal string (e.g., "#FF0000" or "FF0000")
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove leading '#' if present
        if hexSanitized.hasPrefix("#") {
            hexSanitized.removeFirst()
        }

        var rgb: UInt64 = 0
        let scanner = Scanner(string: hexSanitized)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "")
        
        // Parse the hex string into an RGB integer
        if scanner.scanHexInt64(&rgb) {
            let r = Double((rgb & 0xFF0000) >> 16) / 255
            let g = Double((rgb & 0x00FF00) >> 8) / 255
            let b = Double(rgb & 0x0000FF) / 255

            self.init(red: r, green: g, blue: b)
        } else {
            // Fallback to white color if parsing fails
            print("Invalid HEX string: \(hex), falling back to white color.")
            self = .white
        }
    }

    // Converts a Color instance to a hexadecimal string representation (e.g., "#FF0000")
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
        // Default to white if components are unavailable
        return "#FFFFFF"
    }
}
