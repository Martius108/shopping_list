//
//  BoughtItemsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

struct BoughtItemsView: View {

    // Access the model context from the environment
    @Environment(\.modelContext) private var modelContext
    // Set a variable to react onto the color scheme
    @Environment(\.colorScheme) var colorScheme
    // The query is in the main view, so here just the item is declared
    var items: [ShopItem]
    var settings: [ViewSettings]

    var body: some View {
        Section(header: boughtItemsHeader) {
            ForEach(items.filter { $0.isBought }) { item in
                boughtItemRow(item: item)
            }
        }
    }
    
    private var boughtItemsHeader: some View {
        Text("Recently bought")
            .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: 0.92 * UIScreen.main.bounds.width, alignment: .leading)
            .padding(.bottom, 8)
            .padding(.top, 15)
    }

    private func boughtItemRow(item: ShopItem) -> some View {
        HStack {
            Text(item.name)
                .font(.system(size: 18))
                .foregroundColor(themedColor(darkModeColor: .white, lightModeColor: .black))
            Spacer()
            Button {
                withAnimation {
                    item.isBought = false  // Reactivates the item
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
