//
//  InputItemView.swift
//  Shopping List
//
//  Created by Martin Lanius on 24.04.25.
//

import Foundation
import SwiftUI
import SwiftData

struct NewItemInputView: View {
    
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var dataManager: ShopDataManager
    
    @Binding var newItem: String
    @Binding var filteredSuggestions: [String]

    var body: some View {

        TextField("To buy", text: $newItem)
            .padding()
            .background(Color.white.opacity(0.7))
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width)
            .cornerRadius(8)
            .padding(.horizontal)
            .onChange(of: newItem) {
                newItem = newItem.prefix(1).uppercased() + newItem.dropFirst()
                filteredSuggestions = dataManager.allItemNames.filter {
                    !newItem.isEmpty && $0.lowercased().hasPrefix(newItem.lowercased())
                }
            }
            .onSubmit {
                guard !dataManager.allItemNames.contains(where: { $0.lowercased() == newItem.lowercased() }) else {
                    newItem = ""
                    filteredSuggestions = []
                    return
                }
                dataManager.appendItem(name: newItem, context: modelContext)
                newItem = ""
                filteredSuggestions = []
            }

        if !filteredSuggestions.isEmpty {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(filteredSuggestions.prefix(3), id: \.self) { suggestion in
                    Text(suggestion)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .onTapGesture {
                            newItem = suggestion
                            dataManager.appendItem(name: suggestion, context: modelContext)
                            newItem = ""
                            filteredSuggestions = []
                        }
                }
            }
            .frame(maxWidth: 0.9 * UIScreen.main.bounds.width, alignment: .leading)
            .background(Color.white.opacity(0.6))
            .cornerRadius(6)
            .padding(.top, 4)
        }
    }
}
