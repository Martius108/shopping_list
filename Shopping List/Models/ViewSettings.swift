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

    static let systemBackgroundColor = "system"
    static let legacyDefaultBackgroundColor = "#F5E4B5"

    var themeMode: String = ThemeMode.system.rawValue
    @Attribute(.externalStorage) var backgroundImageData: Data?
    var backgroundColor: String = ViewSettings.systemBackgroundColor
    var elementOpacity: Double = 1
    var hasMigratedDefaultAppearance: Bool = false
    var currentListID: UUID?
    var sharedZoneName: String?
    var sharedZoneOwnerName: String?

    init(
        themeMode: String = ThemeMode.system.rawValue,
        backgroundImageData: Data? = nil,
        backgroundColor: String = ViewSettings.systemBackgroundColor,
        elementOpacity: Double = 1,
        hasMigratedDefaultAppearance: Bool = true,
        currentListID: UUID? = nil,
        sharedZoneName: String? = nil,
        sharedZoneOwnerName: String? = nil
    ) {
        
        self.themeMode = ThemeMode(rawValue: themeMode)?.rawValue ?? ThemeMode.system.rawValue
        self.backgroundImageData = backgroundImageData
        self.backgroundColor = backgroundColor
        self.elementOpacity = min(max(elementOpacity, 0), 1)
        self.hasMigratedDefaultAppearance = hasMigratedDefaultAppearance
        self.currentListID = currentListID
        self.sharedZoneName = sharedZoneName
        self.sharedZoneOwnerName = sharedZoneOwnerName
    }

    func migrateDefaultAppearanceIfNeeded() {
        guard !hasMigratedDefaultAppearance else { return }
        defer { hasMigratedDefaultAppearance = true }

        guard
            backgroundImageData == nil,
            backgroundColor.caseInsensitiveCompare(Self.legacyDefaultBackgroundColor) == .orderedSame,
            abs(elementOpacity - 0.7) < 0.001
        else { return }

        backgroundColor = Self.systemBackgroundColor
        elementOpacity = 1
    }

    func applyTheme(_ theme: ThemeMode) {
        themeMode = theme.rawValue
        backgroundImageData = nil
        backgroundColor = Self.systemBackgroundColor
    }
}
