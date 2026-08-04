//
//  ViewSettings.swift
//  Shopping List
//
//  Created by Martin Lanius on 27.04.25.
//

import Foundation
import SwiftData

@Model
// Model class holding the data for user settings
final class ViewSettings {

    var themeMode: String = ThemeMode.system.rawValue
    @Attribute(.externalStorage) var backgroundImageData: Data?
    var backgroundColor: String = "#F5E4B5"
    var elementOpacity: Double = 0.7

    init(themeMode: String = ThemeMode.system.rawValue, backgroundImageData: Data? = nil, backgroundColor: String = "#F5E4B5", elementOpacity: Double = 0.7) {
        
        self.themeMode = ThemeMode(rawValue: themeMode)?.rawValue ?? ThemeMode.system.rawValue
        self.backgroundImageData = backgroundImageData
        self.backgroundColor = backgroundColor
        self.elementOpacity = min(max(elementOpacity, 0), 1)
    }
}
