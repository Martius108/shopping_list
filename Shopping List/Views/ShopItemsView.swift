//
//  ShopItemsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// View for displaying shopping items that are not yet bought
struct ShopItemsView: View {
    
    // Access the model context to interact with the local database
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareManager: ShoppingListShareManager
    // Access the current color scheme (light/dark mode) from the environment
    @Environment(\.colorScheme) var colorScheme
    // Items passed in from the main view
    var items: [ShopItem]
    var settings: ViewSettings
    var list: ShoppingListEntry
    var contentWidth: CGFloat
    
    @State private var editingItemID: UUID?
    @State private var editedName: String = ""
    
    var body: some View {
        
        // Section displaying the list of items that are not bought yet
        Section(header:
                    Text("To buy")
            .font(.subheadline.weight(.semibold))
            .shoppingImageLabelStyle(
                settings.backgroundImageData != nil,
                fallbackColor: sectionHeaderColor
            )
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.bottom, 8)
        ) {
            ForEach(ShoppingListLogic.activeItems(from: items)) { item in
                // Row layout for each shopping item
                HStack {
                    // Display the quantity if greater than 1
                    if (item.amount > 1) {
                        Text("\(item.amount)")
                            .font(.system(size: 18))
                            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                    }
                    // Display the item name or TextField for editing
                    if editingItemID == item.id {
                        TextField("Item name", text: $editedName, onCommit: {
                            saveEditedName(for: item)
                            editingItemID = nil
                        })
                        .font(.system(size: 18))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(item.name)
                            .font(.system(size: 18))
                            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                            .onTapGesture {
                                editingItemID = item.id
                                editedName = item.name
                            }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        // Button to decrease amount or mark as bought if only 1 left
                        Button(action: {
                            if item.amount == 1 {
                                withAnimation {
                                    item.createdAt = Date()
                                    item.isBought = true  // Mark item as bought
                                    item.updatedAt = Date()
                                    do {
                                        try modelContext.save()
                                        syncSharedList()
                                    } catch {
                                        print("Error while saving: \(error.localizedDescription)")
                                    }
                                }
                            } else {
                                let newAmount = item.amount - 1
                                item.amount = newAmount  // Decrease amount
                                item.updatedAt = Date()
                                do {
                                    try modelContext.save()
                                    syncSharedList()
                                } catch {
                                    print("Error while saving: \(error.localizedDescription)")
                                }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .gray))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 9)
                        
                        // Button to increase amount by 1
                        Button(action: {
                            let newAmount = item.amount + 1
                            item.amount = newAmount
                            item.updatedAt = Date()
                            try? modelContext.save() // Save without explicit error handling
                            syncSharedList()
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .gray))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 15)
                        
                        // Button to manually mark the item as bought
                        Button {
                            withAnimation {
                                item.createdAt = Date()
                                item.isBought = true
                                item.updatedAt = Date()
                                do {
                                    try modelContext.save()
                                    syncSharedList()
                                } catch {
                                    print("Error while saving: \(error.localizedDescription)")
                                }
                            }
                        } label: {
                            Image(systemName: "circle")
                                .resizable()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.blue)
                                .scaleEffect(1.1)
                        }
                        .padding(.trailing, 8)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 9)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(maxWidth: contentWidth)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(elementColor(darkModeColor: .black, lightModeColor: .white))
                        .padding(.top, 3)
                )
            }
            .onDelete { indexSet in
                let activeItems = ShoppingListLogic.activeItems(from: items)
                for index in indexSet {
                    let item = activeItems[index]
                    item.deletedAt = Date()
                    item.updatedAt = Date()
                }
                try? modelContext.save()
                syncSharedList()
            }
        }
    }

    private func saveEditedName(for item: ShopItem) {
        let name = ShoppingListLogic.displayName(for: editedName)
        guard !name.isEmpty else {
            editingItemID = nil
            return
        }

        item.name = name
        item.updatedAt = Date()
        do {
            try modelContext.save()
            syncSharedList()
        } catch {
            print("Error while saving edited name: \(error.localizedDescription)")
        }
    }

    private func syncSharedList() {
        Task {
            await shareManager.sync(list: list, modelContext: modelContext)
        }
    }
    
    // Returns a color adjusted for the current theme and user settings
    private func themedColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        let theme = settings.themeMode

        switch ThemeMode(rawValue: theme) {
        case .dark:
            return darkModeColor
        case .light:
            return lightModeColor
        case .system:
            return colorScheme == .dark
                ? darkModeColor
                : lightModeColor
        case nil:
            return lightModeColor
        }
    }

    private func elementColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        themedColor(darkModeColor: darkModeColor, lightModeColor: lightModeColor)
            .opacity(settings.elementOpacity)
    }

    private var sectionHeaderColor: Color {
        settings.backgroundColor == ViewSettings.systemBackgroundColor
            ? .secondary
            : themedColor(darkModeColor: .white, lightModeColor: .black)
    }
}
