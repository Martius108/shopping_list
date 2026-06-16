//
//  ContentView.swift
//  Shopping List
//
//  Created by Martin Lanius on 23.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// Separate view to display either an image or a colored background, fixed to the screen size
struct FixedBackgroundView: View {
    
    var image: UIImage? = nil
    var backgroundColor: Color = .white

    var body: some View {
        // Use GeometryReader to adapt the size without reacting to keyboard appearance
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

// Main view displaying the shopping list
struct ContentView: View {
    
    // Access the model context to interact with the local database
    @Environment(\.modelContext) private var modelContext: ModelContext
    // Query to retrieve and reactively update the list of shopping items, sorted by name
    @Query(sort: \ShopItem.name) var itemsList: [ShopItem]
    
    // Query to retrieve the view settings stored locally or via SwiftData sync if enabled
    @Query var settingsList: [ViewSettings]
        
    // Local state for the currently active settings
    @State private var settings: ViewSettings?
    @State private var isShowingSettings: Bool = false
    
    // Local states for new item input and suggestion filtering
    @State private var filteredSuggestions: [String] = []
    @State private var newItem: String = ""

    var body: some View {
        NavigationStack {
            if let settings = settings {
                ZStack {
                    if let backgroundImageData = settings.backgroundImageData, let image = UIImage(data: backgroundImageData) {
                        // Display the selected background image
                        FixedBackgroundView(image: image)
                    } else {
                        // Display a colored background if no image is set
                        FixedBackgroundView(backgroundColor: Color(hex: settings.backgroundColor))
                    }

                    VStack(spacing: 16) {
                        // Input field and suggestion list for adding new items
                        InputItemView(
                            settings: $settings, newItem: $newItem,
                            filteredSuggestions: $filteredSuggestions
                        )
                        ScrollView {
                            VStack(spacing: 0) {
                                // View listing items that need to be bought
                                ShopItemsView(items: itemsList, settings: settings)
                                // View listing items that have already been bought
                                BoughtItemsView(items: itemsList, settings: settings)
                            }
                        }
                        .padding(.top)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .navigationTitle("Shopping List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Button to open the settings view
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                }
                .navigationDestination(isPresented: $isShowingSettings) {
                    // Open the settings view when the button is tapped
                    SettingsView(settings: Binding(
                        get: { settings },
                        set: { self.settings = $0 }
                    ))
                }
            } else {
                // Show a loading indicator while settings are being loaded
                ProgressView("Loading settings ...")
                    .onAppear {
                        loadSettings()
                    }
            }
        }
    }
    
    // Function to load the view settings from the cloud or create new settings if none exist
    private func loadSettings() {
        if let existingSettings = settingsList.first {
            settings = existingSettings
        } else {
            // Create new settings and save them to the cloud
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
// Preview for Xcode
#Preview {
    ContentView()
        .modelContainer(for: [ShopItem.self, ViewSettings.self])
}
