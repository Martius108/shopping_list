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
    @State private var isPresentingAccount = false
    @State private var isPresentingAbout = false

    var body: some View {
        
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionTitle("Theme Mode")

                Picker("Select Theme", selection: $settings.themeMode) {
                    Text("System").tag(ThemeMode.system.rawValue)
                    Text("Light").tag(ThemeMode.light.rawValue)
                    Text("Dark").tag(ThemeMode.dark.rawValue)
                }
                .pickerStyle(.segmented)
                .shoppingImageLabelStyle(settings, fallbackColor: .primary)
                .onChange(of: settings.themeMode) { _, newValue in
                    settings.applyTheme(ThemeMode(rawValue: newValue) ?? .system)
                    selectedPhoto = nil
                    try? modelContext.save()
                }

                sectionTitle("Background Color")

                ColorPicker("Select Background Color", selection: Binding(
                    get: { Color(shoppingBackground: settings.backgroundColor) },
                    set: { newColor in
                        selectedPhoto = nil
                        settings.backgroundImageData = nil
                        settings.backgroundColor = newColor.toHex()
                        try? modelContext.save()
                    }
                ))
                .shoppingImageLabelStyle(
                    settings,
                    fallbackColor: .primary
                )

                sectionTitle("Background Image")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Select Background Image", systemImage: "photo")
                        .shoppingImageLabelStyle(
                            settings,
                            fallbackColor: .blue
                        )
                }

                sectionTitle("Opacity")

                Slider(value: $settings.elementOpacity, in: 0...1, step: 0.02)
                    .onChange(of: settings.elementOpacity) { _, _ in
                        try? modelContext.save()
                    }
                Text("Opacity: \(settings.elementOpacity, format: .percent.precision(.fractionLength(0)))")
                    .shoppingImageLabelStyle(
                        settings,
                        fallbackColor: .primary
                    )

                Button {
                    isPresentingAccount = true
                } label: {
                    Label("ShoppingList account", systemImage: "person.crop.circle")
                        .shoppingImageLabelStyle(settings, fallbackColor: .blue)
                }
                .buttonStyle(.plain)

                Button { isPresentingAbout = true } label: {
                    Label("About this app", systemImage: "info.circle")
                        .shoppingImageLabelStyle(settings, fallbackColor: .blue)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isPresentingAccount) {
            FirebaseSharingView(list: nil)
        }
        .sheet(isPresented: $isPresentingAbout) { AboutAppView() }
        .background {
            if let data = settings.backgroundImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color(shoppingBackground: settings.backgroundColor).ignoresSafeArea()
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task {
                guard
                    let data = try? await photo.loadTransferable(type: Data.self),
                    selectedPhoto == photo
                else { return }
                settings.backgroundImageData = data
                selectedPhoto = nil
                try? modelContext.save()
            }
        }
        .navigationTitle(settings.backgroundImageData == nil ? Text("Settings") : Text(verbatim: ""))
        .navigationBarTitleDisplayMode(settings.backgroundImageData == nil ? .large : .inline)
        .toolbar(settings.backgroundImageData == nil ? .visible : .hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.backgroundImageData != nil {
                Text("Settings")
                    .font(.title2.bold())
                    .shoppingImageLabelStyle(settings, fallbackColor: .blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .shoppingImageLabelStyle(
                settings,
                fallbackColor: .primary
            )
    }
}
