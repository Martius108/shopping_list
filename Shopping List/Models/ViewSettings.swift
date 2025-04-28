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

    var themeMode: String = "dark"
    var backgroundImageData: Data? = nil
    var backgroundColor: String = "#F5E4B5"
    var elementOpacity: Double = 0.0

    init(themeMode: String = "dark", backgroundImageData: Data? = nil, backgroundColor: String = "#F5E4B5", elementOpacity: Double = 0.5) {
        
        self.themeMode = themeMode
        self.backgroundImageData = backgroundImageData
        self.backgroundColor = backgroundColor
        self.elementOpacity = elementOpacity
    }
}
