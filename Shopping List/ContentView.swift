//
//  ContentView.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// Separate view for a fixed-size background
struct FixedBackgroundView: View {
    
    var image: UIImage? = nil
    var backgroundColor: Color = .white

    var body: some View {
        // Use geometry reader to avoid changes of the image when keyboard is toggled
        GeometryReader { geometry in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Rectangle()
                    .fill(backgroundColor)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .edgesIgnoringSafeArea(.all) // Ensure the background covers the entire screen
    }
}

// Main view for the shopping list
struct ContentView: View {
    
    // Set up all necessary variables and state properties
    @Environment(\.modelContext) private var modelContext: ModelContext
    // Set up a query to react onto changes in the data container
    @Query(sort: \ShopItem.name) var itemsList: [ShopItem]
    
    // Get all settings from iCloud
    @Query var settingsList: [ViewSettings]
        
    // Local state for current settings
    @State private var settings: ViewSettings?
    @State private var isShowingSettings: Bool = false
    
    @State private var filteredSuggestions: [String] = []
    @State private var newItem: String = ""

    var body: some View {
        NavigationStack {
            if let settings = settings {
                ZStack {
                    if let backgroundImageData = settings.backgroundImageData, let image = UIImage(data: backgroundImageData) {
                        FixedBackgroundView(image: image)
                    } else {
                        FixedBackgroundView(backgroundColor: Color(hex: settings.backgroundColor))
                    }

                    VStack(spacing: 16) {
                        InputItemView(
                            settings: $settings, newItem: $newItem,
                            filteredSuggestions: $filteredSuggestions
                        )
                        ScrollView {
                            VStack(spacing: 0) {
                                ShopItemsView(items: itemsList, settings: settingsList)
                                BoughtItemsView(items: itemsList, settings: settingsList)
                            }
                        }
                        .padding(.top)
                    }
                }
                .navigationTitle("Shopping List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.title2)
                                .padding(.bottom, 12)
                                .padding(.trailing, 4)
                        }
                    }
                }
                .navigationDestination(isPresented: $isShowingSettings) {
                    SettingsView(settings: Binding(
                        get: { settings },
                        set: { self.settings = $0 }
                    ))
                }
            } else {
                ProgressView("Loading settings ...")
                    .onAppear {
                        loadSettings()
                }
            }
        }
    }
    
    private func loadSettings() {
        if let existingSettings = settingsList.first {
            settings = existingSettings
        } else {
            // Erzeuge neue Settings und speichere sie in der Cloud
            let newSettings = ViewSettings()
            modelContext.insert(newSettings)
            do {
                try modelContext.save()
                print("Settings saved")
                settings = newSettings
                print("No existing settings found. Created new settings.")
            } catch {
                print("Failed to save new settings: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ShopItem.self, ViewSettings.self])
}
