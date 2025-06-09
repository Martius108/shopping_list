//
//  BoughtItemsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

// View for displaying shopping items that have already been bought
struct BoughtItemsView: View {

    // Access the model context from the environment
    @Environment(\.modelContext) private var modelContext
    // Access the color scheme (light/dark mode) from the environment
    @Environment(\.colorScheme) var colorScheme
    // List of shopping items passed from the parent view
    var items: [ShopItem]
    // List of settings passed from the parent view
    var settings: [ViewSettings]

    var body: some View {
        // Section displaying the list of bought items
        Section(header: boughtItemsHeader) {
            ForEach(items.filter { $0.isBought }.sorted(by: { $0.createdAt > $1.createdAt }).prefix(20)) { item in
                boughtItemRow(item: item)
            }
        }
    }
    
    // Header for the "Recently bought" section
    private var boughtItemsHeader: some View {
        Text("Recently bought")
            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: 0.92 * UIScreen.main.bounds.width, alignment: .leading)
            .padding(.bottom, 8)
            .padding(.top, 15)
    }

    // Row layout for a bought item, with a button to reactivate it
    private func boughtItemRow(item: ShopItem) -> some View {
        HStack {
            // Display the item name
            Text(item.name)
                .font(.system(size: 18))
                .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            Spacer()
            // Button to mark the item as "not bought" again
            Button {
                withAnimation {
                    item.isBought = false
                    do {
                        try modelContext.save()
                    } catch {
                        print("Error while saving: \(error.localizedDescription)")
                    }
                }
            } label: {
                Image(systemName: "arrow.uturn.left")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.green)
                    .scaleEffect(1.1)
            }
            .padding(.trailing, 8)
        }
        .padding(.top, 14)
        .padding(.bottom, 11)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: 0.92 * UIScreen.main.bounds.width)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themedColor(darkModeColor: .black, lightModeColor: .white))
                .padding(.top, 3)
        )
    }
    
    // Returns a color adjusted for the theme mode and user settings
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
