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
    
    // Access the SwiftData model context for performing data operations
    // Observe the data manager to reflect any changes in the UI
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var dataManager: ShopDataManager
    
    var body: some View {
        
        // Display the list of shopping items that are not yet bought
        //List {
            Section(header:
                Text("To Buy")
                .foregroundColor(.white)
            ) {
                ForEach(dataManager.currentItemsList) { item in
                    // Row layout for each individual shopping item
                    HStack {
                        // Display the current quantity of the item
                        Text("\(item.amount)")
                            .font(.system(size: 16, weight: .regular))
                            .frame(minWidth: 20)

                        // Display the name of the item
                        Text(item.name)
                            .font(.system(size: 18, weight: .medium))

                        Spacer()

                        HStack(spacing: 8) {
                            // Decrease the amount; if amount is 1, mark the item as bought instead
                            Button(action: {
                                if item.amount == 1 {
                                    withAnimation {
                                        dataManager.markItemAsBought(item: item, context: modelContext)
                                    }
                                } else {
                                    let newAmount = item.amount - 1
                                    dataManager.updateItemAmount(item: item, amount: newAmount, context: modelContext)
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Increase the amount of the item by 1
                            Button(action: {
                                let newAmount = item.amount + 1
                                dataManager.updateItemAmount(item: item, amount: newAmount, context: modelContext)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Manually mark the item as bought
                            Button {
                                withAnimation {
                                    dataManager.markItemAsBought(item: item, context: modelContext)
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
                }
            }
        //}
        // Optional: hide scroll view background for cleaner appearance
        //.scrollContentBackground(.hidden)
        // Allow the list to expand vertically to take full available height
        //.frame(maxHeight: .infinity)
    }
}
