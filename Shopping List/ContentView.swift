import Foundation
import SwiftData
import SwiftUI

struct FixedBackgroundView: View {
    var image: UIImage?
    var backgroundColor: Color = .white

    var body: some View {
        GeometryReader { geometry in
            if let image {
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
        .ignoresSafeArea()
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var shareManager: ShoppingListShareManager
    @Query(sort: \ShopItem.name) private var items: [ShopItem]
    @Query(sort: \ShoppingListEntry.createdAt) private var lists: [ShoppingListEntry]
    @Query private var storedSettings: [ViewSettings]

    @State private var settings: ViewSettings?
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if let settings, let currentList {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        CurrentShoppingListView(settings: settings, list: currentList, items: items)
                    }
                    .tabItem {
                        Image(systemName: "doc")
                            .accessibilityLabel("Current List")
                    }
                    .tag(0)

                    NavigationStack {
                        AllShoppingListsView(settings: settings, selectedTab: $selectedTab)
                    }
                    .tabItem {
                        Image(systemName: "doc.on.doc")
                            .accessibilityLabel("All Lists")
                    }
                    .tag(1)

                    NavigationStack {
                        SettingsView(
                            settings: Binding(
                                get: { settings },
                                set: { self.settings = $0 }
                            )
                        )
                    }
                    .tabItem {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                    .tag(2)
                }
                .task {
                    await consumeAcceptedShare(settings: settings)
                    await shareManager.restoreCloudLists(settings: settings, modelContext: modelContext)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await consumeAcceptedShare(settings: settings)
                        await shareManager.restoreCloudLists(settings: settings, modelContext: modelContext)
                        if let list = self.currentList {
                            await shareManager.refresh(list: list)
                            await shareManager.sync(list: list, modelContext: modelContext)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .shoppingListShareAccepted)) { _ in
                    Task {
                        await consumeAcceptedShare(settings: settings)
                    }
                }
            } else {
                ProgressView("Loading settings ...")
                    .onAppear(perform: loadData)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .onChange(of: items.count) { _, _ in
            removeDuplicateItems()
        }
    }

    private var currentList: ShoppingListEntry? {
        let visibleLists = ShoppingListLogic.visibleLists(from: lists)
        guard let currentListID = settings?.currentListID else { return visibleLists.first }
        return visibleLists.first(where: { $0.id == currentListID }) ?? visibleLists.first
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.flatMap({ ThemeMode(rawValue: $0.themeMode) }) {
        case .light: .light
        case .dark: .dark
        case .system, nil: nil
        }
    }

    private func loadData() {
        do {
            let settings = storedSettings.first ?? ViewSettings()
            if storedSettings.isEmpty {
                modelContext.insert(settings)
            }
            settings.migrateDefaultAppearanceIfNeeded()

            var savedLists = try modelContext.fetch(FetchDescriptor<ShoppingListEntry>())
            if savedLists.isEmpty {
                let list = ShoppingListEntry(
                    name: String(localized: "Shopping List"),
                    sharedZoneName: settings.sharedZoneName,
                    sharedZoneOwnerName: settings.sharedZoneOwnerName
                )
                modelContext.insert(list)
                savedLists = [list]
                settings.currentListID = list.id
                for item in items {
                    item.listID = list.id
                }
            } else if !savedLists.contains(where: {
                $0.id == settings.currentListID && $0.replacedByListID == nil
            }) {
                settings.currentListID = ShoppingListLogic.visibleLists(from: savedLists).first?.id
            }

            if let currentListID = settings.currentListID {
                for item in items where item.listID == nil {
                    item.listID = currentListID
                }
            }

            ShoppingListLogic.removeDuplicateItems(from: items, modelContext: modelContext)
            try modelContext.save()
            self.settings = settings
        } catch {
            print("Could not initialize shopping lists: \(error.localizedDescription)")
        }
    }

    private func consumeAcceptedShare(settings: ViewSettings) async {
        if await shareManager.consumeAcceptedShare(settings: settings, modelContext: modelContext) != nil {
            selectedTab = 0
        }
    }

    private func removeDuplicateItems() {
        guard ShoppingListLogic.removeDuplicateItems(from: items, modelContext: modelContext) > 0 else {
            return
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            print("Could not consolidate duplicate shopping items: \(error.localizedDescription)")
        }
    }
}

private struct CurrentShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareManager: ShoppingListShareManager

    let settings: ViewSettings
    let list: ShoppingListEntry
    let items: [ShopItem]

    @State private var filteredSuggestions: [String] = []
    @State private var newItem = ""

    var body: some View {
        ZStack {
            if let data = settings.backgroundImageData, let image = UIImage(data: data) {
                FixedBackgroundView(image: image)
            } else {
                FixedBackgroundView(backgroundColor: Color(shoppingBackground: settings.backgroundColor))
            }

            GeometryReader { geometry in
                let contentWidth = contentWidth(for: geometry.size)
                let visibleItems = ShoppingListLogic.visibleItems(from: items, listID: list.id)

                VStack(spacing: 16) {
                    InputItemView(
                        settings: settings,
                        list: list,
                        newItem: $newItem,
                        filteredSuggestions: $filteredSuggestions,
                        contentWidth: contentWidth
                    )

                    ScrollView {
                        VStack(spacing: 0) {
                            ShopItemsView(
                                items: visibleItems,
                                settings: settings,
                                list: list,
                                contentWidth: contentWidth
                            )
                            BoughtItemsView(
                                items: visibleItems,
                                settings: settings,
                                list: list,
                                contentWidth: contentWidth
                            )
                        }
                    }
                    .padding(.top)
                    .refreshable {
                        await shareManager.sync(list: list, modelContext: modelContext)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(settings.backgroundImageData == nil ? list.name : "")
        .navigationBarTitleDisplayMode(settings.backgroundImageData == nil ? .large : .inline)
        .toolbar(settings.backgroundImageData == nil ? .visible : .hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.backgroundImageData != nil {
                Text(list.name)
                    .font(.title2.bold())
                    .shoppingImageLabelStyle(true, fallbackColor: .blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .task(id: list.id) {
            await shareManager.refresh(list: list)
            await shareManager.sync(list: list, modelContext: modelContext)
        }
    }

    private func contentWidth(for size: CGSize) -> CGFloat {
        size.width * (size.width > size.height ? 0.60 : 0.92)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ShopItem.self, ShoppingListEntry.self, ViewSettings.self])
        .environmentObject(ShoppingListShareManager())
}
