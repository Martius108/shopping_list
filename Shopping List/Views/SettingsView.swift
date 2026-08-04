//
//  SettingsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 27.04.25.
//

import Foundation
import SwiftUI
import SwiftData
import PhotosUI

// View for adjusting app settings like theme, background, and opacity
struct SettingsView: View {
    
    // Access the model context to save changes
    @Environment(\.modelContext) private var modelContext
    // Access the current color scheme (light/dark mode)
    @Environment(\.colorScheme) var colorScheme
    // Bind the settings instance to this view
    @Binding var settings: ViewSettings
    
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Theme Mode")
                    .font(.headline)

                Picker("Select Theme", selection: $settings.themeMode) {
                    Text("System").tag(ThemeMode.system.rawValue)
                    Text("Light").tag(ThemeMode.light.rawValue)
                    Text("Dark").tag(ThemeMode.dark.rawValue)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.themeMode) { _, newValue in
                    settings.themeMode = ThemeMode(rawValue: newValue)?.rawValue ?? ThemeMode.system.rawValue
                    try? modelContext.save()
                }

                Text("Background Color")
                    .font(.headline)

                ColorPicker("Select Background Color", selection: Binding(
                    get: { Color(hex: settings.backgroundColor) },
                    set: { newColor in
                        settings.backgroundImageData = nil
                        settings.backgroundColor = newColor.toHex()
                        try? modelContext.save()
                    }
                ))

                Text("Background Image")
                    .font(.headline)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Select Background Image", systemImage: "photo")
                }

                Text("Opacity")
                    .font(.headline)

                Slider(value: $settings.elementOpacity, in: 0...1, step: 0.02)
                    .onChange(of: settings.elementOpacity) { _, _ in
                        try? modelContext.save()
                    }
                Text("Opacity: \(Int(settings.elementOpacity * 100))%")
            }
            .padding()
            .foregroundColor(settings.themeMode == ThemeMode.dark.rawValue ? .white : .primary)
        }
        .scrollIndicators(.hidden)
        .background {
            if let data = settings.backgroundImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color(hex: settings.backgroundColor).ignoresSafeArea()
            }
        }
        .task(id: selectedPhoto) {
            guard let data = try? await selectedPhoto?.loadTransferable(type: Data.self) else {
                return
            }
            settings.backgroundImageData = data
            try? modelContext.save()
        }
        .navigationTitle("Settings")
    }
}
