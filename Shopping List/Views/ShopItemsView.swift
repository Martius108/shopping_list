//
//  ShopItemsView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

struct ShopItemsView: View {
    
    // Access the model context from the environment
    @Environment(\.modelContext) private var modelContext
    // Set a variable to react onto the color scheme
    @Environment(\.colorScheme) var colorScheme
    // The query is in the main view, so here just the item is declared
    var items: [ShopItem]
    
    var body: some View {
        
        // Display the list of shopping items that are not yet bought
        Section(header:
            Text("To buy")
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: 0.92 * UIScreen.main.bounds.width, alignment: .leading)
            .padding(.bottom, 8)
        ) {
            ForEach(items.filter { !$0.isBought}) { item in
                // Row layout for each individual shopping item
                HStack {
                    // Display the current quantity of the item
                    Text("\(item.amount)")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    // Display the name of the item
                    Text(item.name)
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    HStack(spacing: 4) {
                        // Decrease the amount; if amount is 1, mark the item as bought instead
                        Button(action: {
                            if item.amount == 1 {
                                withAnimation {
                                    item.isBought = true  // Mark as bought
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        print("Error while saving: \(error.localizedDescription)")
                                    }
                                }
                            } else {
                                let newAmount = item.amount - 1
                                item.amount = newAmount   // Increase the amount
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("Error while saving: \(error.localizedDescription)")
                                }
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(colorScheme == .dark ? .white : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 9)

                        // Increase the amount of the item by 1
                        Button(action: {
                            let newAmount = item.amount + 1
                            item.amount = newAmount   // Increase the amount
                            try? modelContext.save()  // Save new amount
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                                .foregroundColor(colorScheme == .dark ? .white : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 15)

                        // Manually mark the item as bought
                        Button {
                            withAnimation {
                                item.isBought = true  // Mark as bought
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
                                .foregroundColor(colorScheme == .dark ? .blue : .blue)
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
                        .fill(colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.8))
                        .padding(.top, 3)
                )
            }
        }
    }
}
