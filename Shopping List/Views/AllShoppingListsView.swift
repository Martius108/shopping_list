import CloudKit
import SwiftData
import SwiftUI

struct AllShoppingListsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareManager: ShoppingListShareManager
    @Query(sort: \ShoppingListEntry.createdAt) private var lists: [ShoppingListEntry]

    let settings: ViewSettings
    @Binding var selectedTab: Int

    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var listPendingSharingRemoval: ShoppingListEntry?
    @State private var listPendingDeletion: ShoppingListEntry?
    @State private var sharingList: ShoppingListEntry?
    @State private var presentedShare: CKShare?
    @State private var isPresentingInvitation = false

    var body: some View {
        ZStack {
            if let data = settings.backgroundImageData, let image = UIImage(data: data) {
                FixedBackgroundView(image: image)
            } else {
                FixedBackgroundView(
                    backgroundColor: Color(shoppingBackground: settings.backgroundColor)
                )
            }

            List {
                if let currentList {
                    Section {
                        listRow(currentList, isCurrent: true)
                    } header: {
                        sectionHeader("Current List")
                    }
                }

                Section {
                    if otherLists.isEmpty {
                        Text("No other lists")
                            .foregroundStyle(.secondary)
                            .listRowBackground(rowBackgroundColor)
                    } else {
                        ForEach(otherLists) { list in
                            listRow(list, isCurrent: false)
                        }
                    }
                } header: {
                    sectionHeader("Other Lists")
                }

                Button {
                    newListName = ""
                    isAddingList = true
                } label: {
                    Label("Add List", systemImage: "plus.circle.fill")
                }
                .listRowBackground(rowBackgroundColor)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(settings.backgroundImageData == nil ? Text("Lists") : Text(""))
        .navigationBarTitleDisplayMode(settings.backgroundImageData == nil ? .large : .inline)
        .toolbar(settings.backgroundImageData == nil ? .visible : .hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.backgroundImageData != nil {
                Text("Lists")
                    .font(.title2.bold())
                    .shoppingImageLabelStyle(true, fallbackColor: .blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .alert("Add List", isPresented: $isAddingList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                addList()
            }
            .disabled(ShoppingListLogic.normalizedName(newListName).isEmpty)
        }
        .confirmationDialog(
            sharingRemovalTitle,
            isPresented: Binding(
                get: { listPendingSharingRemoval != nil },
                set: { if !$0 { listPendingSharingRemoval = nil } }
            ),
            presenting: listPendingSharingRemoval
        ) { list in
            Button(sharingRemovalButtonTitle(for: list), role: .destructive) {
                Task { await stopSharing(list) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            Text(sharingRemovalMessage(for: list))
        }
        .confirmationDialog(
            "Delete List?",
            isPresented: Binding(
                get: { listPendingDeletion != nil },
                set: { if !$0 { listPendingDeletion = nil } }
            ),
            presenting: listPendingDeletion
        ) { list in
            Button("Delete List", role: .destructive) {
                Task { await delete(list) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            Text(deletionMessage(for: list))
        }
        .sheet(isPresented: $isPresentingInvitation, onDismiss: {
            guard let sharingList else { return }
            Task {
                await shareManager.refresh(list: sharingList)
                try? modelContext.save()
                self.sharingList = nil
                presentedShare = nil
            }
        }) {
            if let presentedShare {
                ShoppingListCloudShareSheet(
                    share: presentedShare,
                    container: shareManager.container
                )
            }
        }
        .alert(
            "Action could not be completed",
            isPresented: Binding(
                get: { shareManager.alertMessage != nil },
                set: { if !$0 { shareManager.dismissAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                shareManager.dismissAlert()
            }
        } message: {
            Text(shareManager.alertMessage ?? "")
        }
    }

    private var currentList: ShoppingListEntry? {
        visibleLists.first(where: { $0.id == settings.currentListID }) ?? visibleLists.first
    }

    private var otherLists: [ShoppingListEntry] {
        visibleLists.filter { $0.id != currentList?.id }
    }

    private var visibleLists: [ShoppingListEntry] {
        ShoppingListLogic.visibleLists(from: lists)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .shoppingImageLabelStyle(
                settings.backgroundImageData != nil,
                fallbackColor: .secondary
            )
    }

    private func listRow(_ list: ShoppingListEntry, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                guard !isCurrent else { return }
                select(list)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: list.isShared ? "person.2.fill" : "doc")
                        .foregroundStyle(.tint)
                    Text(list.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 24) {
                if list.isShared {
                    Button {
                        listPendingSharingRemoval = list
                    } label: {
                        Image(systemName: "person.2.slash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(
                        isReceivedList(list) ? "Leave Shared List" : "Remove Sharing"
                    )
                } else {
                    Button {
                        Task { await share(list) }
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Grant Access")
                }

                if !isReceivedList(list) {
                    Button(role: .destructive) {
                        listPendingDeletion = list
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete List")
                }
            }
        }
        .listRowBackground(rowBackgroundColor)
        .disabled(shareManager.isWorking)
    }

    private var rowBackgroundColor: Color {
        themedColor(darkModeColor: .black, lightModeColor: .white)
            .opacity(settings.elementOpacity)
    }

    private func themedColor(darkModeColor: Color, lightModeColor: Color) -> Color {
        switch ThemeMode(rawValue: settings.themeMode) {
        case .dark:
            darkModeColor
        case .light:
            lightModeColor
        case .system:
            Color(uiColor: .systemBackground)
        case nil:
            lightModeColor
        }
    }

    private var sharingRemovalTitle: LocalizedStringKey {
        guard let list = listPendingSharingRemoval else { return "Remove Sharing?" }
        return isReceivedList(list) ? "Leave Shared List?" : "Remove Sharing?"
    }

    private func sharingRemovalButtonTitle(for list: ShoppingListEntry) -> LocalizedStringKey {
        isReceivedList(list) ? "Leave Shared List" : "Remove Sharing"
    }

    private func sharingRemovalMessage(for list: ShoppingListEntry) -> LocalizedStringKey {
        if isReceivedList(list) {
            return "You will lose access to this list. The owner and other participants keep it."
        }
        return "Other participants will lose access. The list and its items remain available to you."
    }

    private func deletionMessage(for list: ShoppingListEntry) -> LocalizedStringKey {
        list.isShared
            ? "The list and all its items will be permanently deleted for you and all participants."
            : "The list and all its items will be permanently deleted."
    }

    private func isReceivedList(_ list: ShoppingListEntry) -> Bool {
        list.sharedZoneOwnerName != nil
            && list.sharedZoneOwnerName != CKCurrentUserDefaultName
    }

    private func share(_ list: ShoppingListEntry) async {
        guard let share = await shareManager.prepareShare(
            list: list,
            modelContext: modelContext
        ) else { return }
        sharingList = list
        presentedShare = share
        isPresentingInvitation = true
    }

    private func stopSharing(_ list: ShoppingListEntry) async {
        if await shareManager.stopSharing(
            list: list,
            settings: settings,
            modelContext: modelContext
        ) {
            listPendingSharingRemoval = nil
        }
    }

    private func delete(_ list: ShoppingListEntry) async {
        if await shareManager.deleteList(
            list,
            settings: settings,
            modelContext: modelContext
        ) {
            listPendingDeletion = nil
        }
    }

    private func select(_ list: ShoppingListEntry) {
        settings.currentListID = list.id
        do {
            try modelContext.save()
            selectedTab = 0
        } catch {
            print("Could not select shopping list: \(error.localizedDescription)")
        }
    }

    private func addList() {
        let name = ShoppingListLogic.normalizedName(newListName)
        guard !name.isEmpty else { return }

        let list = ShoppingListEntry(name: name)
        modelContext.insert(list)
        settings.currentListID = list.id
        do {
            try modelContext.save()
            selectedTab = 0
        } catch {
            print("Could not add shopping list: \(error.localizedDescription)")
        }
    }
}
