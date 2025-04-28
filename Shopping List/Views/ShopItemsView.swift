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
    // Access the current color scheme (light/dark mode) from the environment
    @Environment(\.colorScheme) var colorScheme
    // Items passed in from the main view
    var items: [ShopItem]
    var settings: [ViewSettings]
    
    var body: some View {
        
        // Section displaying the list of items that are not bought yet
        Section(header:
                    Text("To buy")
            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: 0.92 * UIScreen.main.bounds.width, alignment: .leading)
            .padding(.bottom, 8)
        ) {
            ForEach(items.filter { !$0.isBought}) { item in
                // Row layout for each shopping item
                HStack {
                    // Display the quantity if greater than 1
                    if (item.amount > 1) {
                        Text("\(item.amount)")
                            .font(.system(size: 18))
                            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                    }
                    // Display the item name
                    Text(item.name)
                        .font(.system(size: 18))
                        .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        // Button to decrease amount or mark as bought if only 1 left
                        Button(action: {
                            if item.amount == 1 {
                                withAnimation {
                                    item.isBought = true  // Mark item as bought
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Error while saving: \(error.localizedDescription)")
                                    }
                                }
                            } else {
                                let newAmount = item.amount - 1
                                item.amount = newAmount  // Decrease amount
                                do {
                                    try modelContext.save()
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
                            try? modelContext.save() // Save without explicit error handling
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
                                item.isBought = true
                                do {
                                    try modelContext.save()
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
                .frame(maxWidth: 0.92 * UIScreen.main.bounds.width)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themedColor(darkModeColor: .black, lightModeColor: .white))
                        .padding(.top, 3)
                )
            }
        }
    }
    
    // Returns a color adjusted for the current theme and user settings
    private func themedColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        let theme = settings[0].themeMode
        let elementOpacity = settings[0].elementOpacity

        switch theme {
        case "dark":
            return darkModeColor.opacity(0.8)
        case "light":
            return lightModeColor.opacity(elementOpacity)
        case "system":
            return colorScheme == .dark
                ? darkModeColor.opacity(0.8)
                : lightModeColor.opacity(elementOpacity)
        default:
            return lightModeColor.opacity(elementOpacity)
        }
    }
}
