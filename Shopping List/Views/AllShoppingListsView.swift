import CloudKit
import SwiftData
import SwiftUI

struct AllShoppingListsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareManager: ShoppingListShareManager
    @EnvironmentObject private var firebase: FirebaseShoppingListManager
    @Query(sort: \ShoppingListEntry.createdAt) private var lists: [ShoppingListEntry]
    @Query private var items: [ShopItem]

    let settings: ViewSettings
    @Binding var selectedTab: Int

    @AppStorage("pendingFirebaseSharingListID") private var pendingSharingID = ""
    @State private var isAddingList = false
    @State private var firebaseList: ShoppingListEntry?
    @State private var newListName = ""
    @State private var renamedListName = ""
    @State private var listPendingRenaming: ShoppingListEntry?
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if shareManager.isWorking {
                        ProgressView("Please wait…").frame(maxWidth: .infinity).padding(.bottom, 12)
                    }
                    if let resumableList {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sharing not finished")
                                .font(.headline)
                            Text(resumableList.name)
                            Text("Continue here with your existing account to finish sharing this list.")
                                .font(.subheadline)
                            Button("Continue sharing", systemImage: "arrow.right.circle") {
                                continueSharing(resumableList)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(rowBackground)
                        .padding(.bottom, 16)
                    }
                    if let currentList {
                        sectionHeader("Current List")
                        listRow(currentList, isCurrent: true)
                    }

                    Button {
                        newListName = ""
                        isAddingList = true
                    } label: {
                        Label("Add List", systemImage: "plus.circle.fill")
                            .padding(.top, 12)
                            .padding(.bottom, 9)
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowBackground)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .padding(.top, 15)


                    sectionHeader("Other Lists")
                        .padding(.top, currentList == nil ? 0 : 15)

                    if otherLists.isEmpty {
                        Text("No other lists")
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.bottom, 9)
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowBackground)
                    } else {
                        ForEach(otherLists) { list in
                            listRow(list, isCurrent: false)
                        }
                    }

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(settings.backgroundImageData == nil ? Text("Lists") : Text(verbatim: ""))
        .navigationBarTitleDisplayMode(settings.backgroundImageData == nil ? .large : .inline)
        .toolbar(settings.backgroundImageData == nil ? .visible : .hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if settings.backgroundImageData != nil {
                Text("Lists")
                    .font(.title2.bold())
                    .shoppingImageLabelStyle(settings, fallbackColor: .blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .sheet(item: $firebaseList) { list in
            FirebaseSharingView(list: list)
        }
        .alert("Add List", isPresented: $isAddingList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                addList()
            }
            .disabled(ShoppingListLogic.listName(newListName) == nil)
        }
        .alert("Rename List", isPresented: Binding(
            get: { listPendingRenaming != nil },
            set: { if !$0 { listPendingRenaming = nil } }
        ), presenting: listPendingRenaming) { list in
            TextField("List name", text: $renamedListName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                let name = renamedListName
                Task { await shareManager.renameList(list, to: name, modelContext: modelContext) }
            }
            .disabled(ShoppingListLogic.listName(renamedListName) == nil)
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
        ShoppingListLogic.otherLists(from: lists, currentID: currentList?.id, firebaseUserID: firebase.user?.uid)
            .filter { list in
            guard list.id.uuidString != pendingSharingID || list.firebaseSharingReady else { return false }
            if let currentList, currentList.firebaseListID != nil, !currentList.firebaseSharingReady,
               let uid = firebase.user?.uid {
                return ShoppingListLogic.unfinishedFirebaseCopy(of: list, lists: [currentList],
                    items: items, userID: uid) == nil
            }
            return true
        }
    }

    private var resumableList: ShoppingListEntry? {
        ShoppingListLogic.sharingToResume(from: lists, pendingID: pendingSharingID,
            firebaseUserID: firebase.user?.uid)
    }

    private func continueSharing(_ list: ShoppingListEntry) {
        pendingSharingID = list.id.uuidString
        firebaseList = list
    }

    private var visibleLists: [ShoppingListEntry] {
        ShoppingListLogic.visibleLists(from: lists, firebaseUserID: firebase.user?.uid)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .shoppingImageLabelStyle(
                settings,
                fallbackColor: .secondary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func listRow(_ list: ShoppingListEntry, isCurrent: Bool) -> some View {
        let received = isReceivedList(list)
        let shared = list.firebaseListID != nil ? list.firebaseSharingReady : list.isShared
        return HStack(spacing: 12) {
            Button {
                guard !isCurrent, listPendingRenaming == nil else { return }
                select(list)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: received ? "person.2.fill" : "doc")
                        .foregroundStyle(.tint)
                    Text(list.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                guard !received else { return }
                renamedListName = list.name
                listPendingRenaming = list
            })
            .accessibilityActions {
                if !received {
                    Button("Rename List") {
                        renamedListName = list.name
                        listPendingRenaming = list
                    }
                }
            }

            HStack(spacing: 24) {
                if !received {
                    if list.firebaseListID != nil {
                        Button { firebaseList = list } label: {
                            Image(systemName: shared && isCurrent ? "person.2" : "person.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(shared && isCurrent ? LocalizedStringKey("People with access") : LocalizedStringKey("Grant Access"))
                    } else {
                        sharingMenu(for: list, isCurrent: isCurrent)
                    }
                }
                if received || (!isCurrent && shared) {
                    Button { listPendingSharingRemoval = list } label: {
                        Image(systemName: "person.2.slash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(received ? "Leave Shared List" : "Remove Sharing")
                }
                if !received && (isCurrent || !shared) {
                    Button(role: .destructive) { listPendingDeletion = list } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete List")
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 9)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(rowBackground)
        .disabled(shareManager.isWorking)
    }

    private func sharingMenu(for list: ShoppingListEntry, isCurrent: Bool) -> some View {
        Menu {
            Button("Apple / iCloud", systemImage: "icloud") {
                Task { await share(list) }
            }
            Button("Android account", systemImage: "person.2") { continueSharing(list) }
        } label: {
            Image(systemName: list.isShared && isCurrent ? "person.2" : "person.badge.plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.tint)
        .accessibilityLabel(list.isShared ? LocalizedStringKey("People with access") : LocalizedStringKey("Grant Access"))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(rowBackgroundColor)
            .padding(.top, 3)
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
        (list.isShared || list.firebaseListID != nil)
            ? "The list and all its items will be permanently deleted for you and all participants."
            : "The list and all its items will be permanently deleted."
    }

    private func isReceivedList(_ list: ShoppingListEntry) -> Bool {
        ShoppingListLogic.isReceivedList(list, firebaseUserID: firebase.user?.uid)
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
        guard let name = ShoppingListLogic.listName(newListName) else { return }

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
