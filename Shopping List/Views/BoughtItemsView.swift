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
    
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var dataManager: ShopDataManager
    
    var body: some View {
        
        //List {
            Section(header: Text("Recently Bought")) {
                ForEach(dataManager.boughtItemsList) { item in
                    HStack {
                        Text(item.name)
                            .font(.system(size: 16))
                        Spacer()
                        Button {
                            withAnimation {
                                dataManager.reactivateItem(item)
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
                }
            }
        //}
        //.scrollContentBackground(.hidden)
    }
}
