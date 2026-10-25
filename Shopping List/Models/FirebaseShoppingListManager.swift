import FirebaseAuth
import FirebaseFirestore
import SwiftData
import SwiftUI

@MainActor
final class FirebaseShoppingListManager: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var members: [String: [String]] = [:]
    @Published var receivedInvitation: ShoppingListInvitation? = UserDefaults.standard.string(forKey: "receivedFirebaseInvitation").flatMap { try? ShoppingListInvitation(link: $0) }
    @Published private(set) var emailSignInLink: String?
    @Published private(set) var emailLinkInProgress = false
    var emailLinkAddress: String { UserDefaults.standard.string(forKey: "emailLinkAddress") ?? "" }
    @Published var alertMessage: String?

    private var context: ModelContext?
    private var settings: ViewSettings?
    private var authListener: AuthStateDidChangeListenerHandle?
    private var listsListener: ListenerRegistration?
    private var itemListeners: [String: ListenerRegistration] = [:]
    private var confirmedListIDs = Set<String>()
    private var grantingListIDs = Set<UUID>()
    private var deletingListIDs = Set<String>()
    private var syncingLists = Set<UUID>()
    private var syncAgain = Set<UUID>()

    func start(context: ModelContext, settings: ViewSettings) {
        guard self.context == nil else { return }
        self.context = context
        self.settings = settings
        user = Auth.auth().currentUser
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.updateSession(user) }
        }
    }

    func refreshSession() async throws {
        try await Auth.auth().currentUser?.reload()
        _ = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: true)
        updateSession(Auth.auth().currentUser)
    }

    func sendEmailSignInLink(_ email: String) async throws {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.count <= 254,
              address.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            throw sharingError("Enter a valid email address.")
        }
        let settings = ActionCodeSettings()
        settings.url = URL(string: "https://shoppinglist-6c6f4.web.app/login/")
        settings.handleCodeInApp = true
        settings.setIOSBundleID("com.martinlanius.Shopping-List")
        settings.setAndroidPackageName("com.martinlanius.shoppinglist", installIfNotAvailable: false, minimumVersion: nil)
        try await Auth.auth().sendSignInLink(toEmail: address, actionCodeSettings: settings)
        UserDefaults.standard.set(address, forKey: "emailLinkAddress")
    }

    func completeEmailSignIn(_ email: String) async throws {
        guard let link = emailSignInLink, !emailLinkInProgress else { return }
        emailLinkInProgress = true
        defer { emailLinkInProgress = false }
        _ = try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), link: link)
        emailSignInLink = nil
        UserDefaults.standard.removeObject(forKey: "emailLinkAddress")
        updateSession(Auth.auth().currentUser)
    }

    func closeEmailSignIn() { emailSignInLink = nil }

    func signOut() throws {
        try Auth.auth().signOut()
        UserDefaults.standard.removeObject(forKey: "emailLinkAddress")
        emailSignInLink = nil
        updateSession(nil)
    }

    private func updateSession(_ user: User?) {
        listsListener?.remove()
        itemListeners.values.forEach { $0.remove() }
        itemListeners.removeAll()
        members.removeAll()
        confirmedListIDs.removeAll()
        if self.user?.uid != user?.uid { deletingListIDs.removeAll() }
        self.user = user
        ensureCurrentList()
        guard let user, user.isEmailVerified, let email = user.email?.lowercased() else { return }
        let uid = user.uid
        listsListener = Firestore.firestore().collection("shoppingLists")
            .whereField("memberEmails", arrayContains: email)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.user?.uid == uid else { return }
                    if let error { self.alertMessage = error.localizedDescription; return }
                    guard let snapshot else { return }
                    do {
                        for change in snapshot.documentChanges(includeMetadataChanges: true) {
                            try self.applyList(change.document, removed: change.type == .removed, uid: uid)
                        }
                        // A fresh subscription has no removed events for access lost while the app was closed.
                        if !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites,
                           let context = self.context {
                            let availableIDs = Set(snapshot.documents.map(\.documentID))
                            for list in try context.fetch(FetchDescriptor<ShoppingListEntry>())
                                where list.firebaseAccountID == uid {
                                guard let id = list.firebaseListID, !availableIDs.contains(id) else { continue }
                                list.firebaseAccessRevoked = true
                                self.itemListeners.removeValue(forKey: id)?.remove()
                                self.members.removeValue(forKey: id)
                            }
                        }
                        try self.context?.save()
                        self.ensureCurrentList()
                    } catch { self.alertMessage = error.localizedDescription }
                }
            }
    }

    private func ensureCurrentList() {
        guard let context, let settings else { return }
        do {
            let lists = try context.fetch(FetchDescriptor<ShoppingListEntry>())
            let visible = ShoppingListLogic.visibleLists(from: lists, firebaseUserID: user?.uid)
            if visible.contains(where: { $0.id == settings.currentListID }) { return }
            if let replacement = visible.first {
                settings.currentListID = replacement.id
            } else {
                let replacement = ShoppingListEntry(name: String(localized: "Shopping List"))
                context.insert(replacement)
                settings.currentListID = replacement.id
            }
            try context.save()
        } catch { alertMessage = error.localizedDescription }
    }

    private func applyList(_ document: QueryDocumentSnapshot, removed: Bool, uid: String) throws {
        // A local pending root does not grant server access to its items yet.
        guard let context, !document.metadata.hasPendingWrites else { return }
        let data = document.data()
        let cached = try context.fetch(FetchDescriptor<ShoppingListEntry>()).filter {
            $0.firebaseListID == document.documentID && $0.firebaseAccountID == uid
        }
        let existing = cached.first
        let unavailable = removed || data["deleted"] as? Bool == true
        if unavailable {
            cached.forEach { $0.firebaseAccessRevoked = true }
            itemListeners.removeValue(forKey: document.documentID)?.remove()
            members.removeValue(forKey: document.documentID)
            return
        }
        guard let name = data["name"] as? String,
              let ownerID = data["ownerID"] as? String,
              let emails = data["memberEmails"] as? [String] else { return }
        let list = existing ?? ShoppingListEntry(name: name)
        if existing == nil { context.insert(list) }
        for entry in cached.isEmpty ? [list] : cached {
            entry.name = name
            entry.firebaseListID = document.documentID
            entry.firebaseOwnerID = ownerID
            entry.firebaseAccountID = uid
            entry.firebaseAccessRevoked = false
            entry.firebaseSharingReady = data["sharingReady"] as? Bool ?? (emails.count > 1)
        }
        // Older uploads have no completion flag; keep the owner's unfinished attempt resumable.
        if data["sharingReady"] == nil, emails.count == 1, ownerID == uid,
           (UserDefaults.standard.string(forKey: "pendingFirebaseSharingListID") ?? "").isEmpty {
            UserDefaults.standard.set(list.id.uuidString, forKey: "pendingFirebaseSharingListID")
        }
        let id = document.documentID
        members[id] = emails
        if !document.metadata.isFromCache { confirmedListIDs.insert(id) }
        guard confirmedListIDs.contains(id), !deletingListIDs.contains(id) else { return }
        guard itemListeners[id] == nil else { return }
        itemListeners[id] = document.reference.collection("items")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.user?.uid == uid, !self.deletingListIDs.contains(id) else { return }
                    do {
                        // SwiftData can merge duplicate cache entries after iCloud synchronization.
                        guard let list = try self.cachedList(id: id, accountID: uid) else { return }
                        if let error { self.alertMessage = error.localizedDescription; return }
                        guard let snapshot else { return }
                        try self.merge(snapshot.documents, into: list)
                        try self.context?.save()
                        if !snapshot.metadata.isFromCache {
                            Task { await self.sync(list: list) }
                        }
                    } catch { self.alertMessage = error.localizedDescription }
                }
            }
        Task { await sync(list: list) }
    }

    private func cachedList(id: String, accountID: String) throws -> ShoppingListEntry? {
        try context?.fetch(FetchDescriptor<ShoppingListEntry>()).first {
            !$0.isDeleted && !$0.firebaseAccessRevoked && $0.replacedByListID == nil
                && $0.firebaseListID == id && $0.firebaseAccountID == accountID
        }
    }

    func grantAccess(to email: String, list: ShoppingListEntry) async throws -> ShoppingListEntry {
        guard let context, let user, user.isEmailVerified, let ownerEmail = user.email?.lowercased() else {
            throw sharingError("Confirm your email address before sharing.")
        }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.count <= 254,
              email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            throw sharingError("Enter a valid email address.")
        }
        _ = try await user.getIDToken(forcingRefresh: true)
        let lists = try context.fetch(FetchDescriptor<ShoppingListEntry>())
        let items = try context.fetch(FetchDescriptor<ShopItem>())
        let copies = ShoppingListLogic.firebaseCopies(of: list, lists: lists, items: items, userID: user.uid)
        guard copies.count <= 1 else {
            throw sharingError("Select the existing shared list to manage its access.")
        }
        let draft = copies.first
        let target: ShoppingListEntry
        if list.firebaseListID == nil, let draft { target = draft }
        else if list.firebaseListID == nil && list.sharedZoneName != nil {
            target = ShoppingListEntry(name: list.name)
            target.firebaseSourceListID = list.id
            context.insert(target)
            for item in try localItems(for: list) {
                let copy = ShopItem(name: item.name, amount: item.amount, isBought: item.isBought,
                                    createdAt: item.createdAt, updatedAt: item.updatedAt,
                                    deletedAt: item.deletedAt, listID: target.id)
                copy.id = item.id
                context.insert(copy)
            }
        } else { target = list }
        if target.id != list.id { target.firebaseSourceListID = list.id }
        if target.firebaseListID != nil {
            guard target.firebaseAccountID == user.uid, target.firebaseOwnerID == user.uid else {
                throw sharingError("Only the owner can change access to this list.")
            }
        }
        grantingListIDs.insert(target.id)
        defer { grantingListIDs.remove(target.id) }
        let isNew = target.firebaseListID == nil
        let reference = Firestore.firestore().collection("shoppingLists")
            .document(target.firebaseListID ?? UUID().uuidString)
        target.firebaseListID = reference.documentID
        target.firebaseOwnerID = user.uid
        target.firebaseAccountID = user.uid
        if !target.firebaseSharingReady {
            UserDefaults.standard.set(target.id.uuidString, forKey: "pendingFirebaseSharingListID")
        }
        try context.save()
        var step: String.LocalizationValue = "The list could not be saved."
        do {
            var data: [String: Any] = [
                "name": target.name, "ownerID": user.uid, "ownerEmail": ownerEmail,
                "memberEmails": FieldValue.arrayUnion([ownerEmail]), "deleted": false
            ]
            if isNew { data["sharingReady"] = false }
            try await reference.setData(data, merge: true)
            step = "The items could not be uploaded."
            try await uploadItems(for: target)
            guard self.user?.uid == user.uid else { throw sharingError("Sign in again to continue.") }
            step = "Access could not be granted."
            try await reference.updateData([
                "memberEmails": FieldValue.arrayUnion([email]), "sharingReady": true
            ])
            target.firebaseSharingReady = true
            settings?.currentListID = target.id
            if UserDefaults.standard.string(forKey: "pendingFirebaseSharingListID") == target.id.uuidString {
                UserDefaults.standard.removeObject(forKey: "pendingFirebaseSharingListID")
            }
            try context.save()
            return target
        } catch {
            throw NSError(domain: "ShoppingListSharing", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(String(localized: step)) \(error.localizedDescription)",
                NSUnderlyingErrorKey: error
            ])
        }
    }

    func receiveInvitation(_ url: URL) {
        if url.scheme == "https", ["shoppinglist-6c6f4.web.app", "shoppinglist-6c6f4.firebaseapp.com"].contains(url.host ?? ""),
           url.path.hasPrefix("/__/auth/links") {
            guard Auth.auth().isSignIn(withEmailLink: url.absoluteString) else {
                alertMessage = String(localized: "This sign-in link is invalid. Request a new link.")
                return
            }
            emailSignInLink = url.absoluteString
            // Never take the sign-in email from a return URL.
            let address = emailLinkAddress
            if !address.isEmpty {
                Task {
                    do { try await completeEmailSignIn(address) }
                    catch { alertMessage = String(localized: "This sign-in link could not be used. Request a new link.") }
                }
            }
            return
        }
        guard url.scheme == "shoppinglist" ||
                (url.scheme == "https" && url.host == "shoppinglist-6c6f4.web.app" && url.path == "/invite/") else { return }
        do {
            receivedInvitation = try ShoppingListInvitation(link: url.absoluteString)
            UserDefaults.standard.set(url.absoluteString, forKey: "receivedFirebaseInvitation")
        } catch { alertMessage = error.localizedDescription }
    }

    func closeInvitation() {
        receivedInvitation = nil
        UserDefaults.standard.removeObject(forKey: "receivedFirebaseInvitation")
    }

    func openInvitation() async throws {
        guard let invitation = receivedInvitation, let user, user.isEmailVerified,
              user.email?.lowercased() == invitation.email.lowercased(), let context else { return }
        do {
            let snapshot = try await Firestore.firestore().collection("shoppingLists")
                .whereField("memberEmails", arrayContains: invitation.email.lowercased()).getDocuments(source: .server)
            guard let document = snapshot.documents.first(where: { $0.documentID == invitation.listID }),
                  document.data()["sharingReady"] as? Bool == true, document.data()["deleted"] as? Bool != true,
                  self.user?.uid == user.uid else { throw sharingError("This invitation is no longer available for your account. Check the invited email and try again.") }
            try applyList(document, removed: false, uid: user.uid)
            guard let list = try cachedList(id: invitation.listID, accountID: user.uid) else {
                throw sharingError("This invitation is no longer available for your account. Check the invited email and try again.")
            }
            settings?.currentListID = list.id
            try context.save()
            closeInvitation()
        } catch {
            throw sharingError("This invitation is unavailable or the server could not be reached. Check the invited email and try again.")
        }
    }

    func removeMember(_ email: String, from list: ShoppingListEntry) async throws {
        guard let user, list.firebaseOwnerID == user.uid, list.firebaseAccountID == user.uid,
              let id = list.firebaseListID, email != user.email?.lowercased() else {
            throw sharingError("Only the owner can change access to this list.")
        }
        try await Firestore.firestore().collection("shoppingLists").document(id)
            .updateData(["memberEmails": FieldValue.arrayRemove([email]),
                         "sharingReady": (members[id] ?? []).filter { $0 != email }.count > 1])
    }

    func stopSharing(_ list: ShoppingListEntry) async throws {
        guard let user, let email = user.email?.lowercased(), list.firebaseAccountID == user.uid,
              let id = list.firebaseListID else { throw sharingError("Sign in again to continue.") }
        let reference = Firestore.firestore().collection("shoppingLists").document(id)
        if list.firebaseOwnerID == user.uid {
            try await reference.updateData(["memberEmails": [email], "sharingReady": false])
        } else {
            try await reference.updateData(["memberEmails": FieldValue.arrayRemove([email])])
        }
    }

    func renameList(_ list: ShoppingListEntry, to value: String) async throws {
        guard let name = ShoppingListLogic.listName(value) else {
            throw sharingError("Enter a list name with 1 to 1000 characters.")
        }
        guard let user, user.isEmailVerified, list.firebaseOwnerID == user.uid,
              list.firebaseAccountID == user.uid, let id = list.firebaseListID else {
            throw sharingError("Only the owner can rename this list.")
        }
        try await Firestore.firestore().collection("shoppingLists").document(id).updateData(["name": name])
        list.name = name
        try context?.save()
    }

    func deleteList(_ list: ShoppingListEntry) async throws {
        guard let user, list.firebaseOwnerID == user.uid, list.firebaseAccountID == user.uid,
              let id = list.firebaseListID else {
            throw sharingError("Only the owner can change access to this list.")
        }
        try await purgeList(Firestore.firestore().collection("shoppingLists").document(id))
    }

    private func purgeList(_ reference: DocumentReference) async throws {
        let id = reference.documentID
        // Stop item listeners before deleting their parent; queued callbacks can otherwise report permission errors.
        deletingListIDs.insert(id)
        itemListeners.removeValue(forKey: id)?.remove()
        confirmedListIDs.remove(id)
        do {
            try await reference.updateData(["deleted": true])
            while true {
                let items = try await reference.collection("items").limit(to: 400).getDocuments(source: .server)
                if items.isEmpty { break }
                let batch = Firestore.firestore().batch()
                items.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
            try await reference.delete()
        } catch {
            deletingListIDs.remove(id)
            updateSession(user)
            throw error
        }
    }

    func sync(list: ShoppingListEntry) async {
        guard !list.isDeleted, !grantingListIDs.contains(list.id), let user, user.isEmailVerified, list.firebaseAccountID == user.uid,
              !list.firebaseAccessRevoked, let id = list.firebaseListID,
              confirmedListIDs.contains(id), !deletingListIDs.contains(id) else { return }
        let localID = list.id
        guard !syncingLists.contains(localID) else { syncAgain.insert(localID); return }
        syncingLists.insert(localID)
        defer { syncingLists.remove(localID) }
        repeat {
            syncAgain.remove(localID)
            do {
                let snapshot = try await Firestore.firestore().collection("shoppingLists")
                    .document(id).collection("items").getDocuments()
                guard self.user?.uid == user.uid, !deletingListIDs.contains(id),
                      let currentList = try cachedList(id: id, accountID: user.uid) else { return }
                try merge(snapshot.documents, into: currentList)
                try context?.save()
                try await uploadItems(for: currentList, remoteDocuments: snapshot.documents)
            } catch {
                if !deletingListIDs.contains(id) { alertMessage = error.localizedDescription }
            }
        } while syncAgain.contains(localID)
    }

    private func localItems(for list: ShoppingListEntry) throws -> [ShopItem] {
        guard let context else { return [] }
        return ShoppingListLogic.uniqueItems(from: try context.fetch(FetchDescriptor<ShopItem>())
            .filter { $0.listID == list.id })
    }

    private func merge(_ documents: [QueryDocumentSnapshot], into list: ShoppingListEntry) throws {
        guard let context else { return }
        var localByID = Dictionary(uniqueKeysWithValues: try localItems(for: list).map { ($0.id, $0) })
        for document in documents {
            let data = document.data()
            guard let id = UUID(uuidString: document.documentID),
                  let name = data["name"] as? String,
                  let amount = data["amount"] as? Int, amount > 0,
                  let isBought = data["isBought"] as? Bool,
                  let createdAt = data["createdAt"] as? Timestamp,
                  let updatedAt = data["updatedAt"] as? Timestamp else { continue }
            if let existing = localByID[id], existing.updatedAt >= updatedAt.dateValue() { continue }
            let item = localByID[id] ?? ShopItem(name: name, listID: list.id)
            if localByID[id] == nil { context.insert(item); localByID[id] = item }
            item.id = id
            item.name = name
            item.amount = amount
            item.isBought = isBought
            item.createdAt = createdAt.dateValue()
            item.updatedAt = updatedAt.dateValue()
            item.deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue()
        }
    }

    private func uploadItems(
        for list: ShoppingListEntry, remoteDocuments: [QueryDocumentSnapshot] = []
    ) async throws {
        guard let uid = user?.uid, list.firebaseAccountID == uid, let id = list.firebaseListID else { return }
        let collection = Firestore.firestore().collection("shoppingLists").document(id).collection("items")
        let remoteDates = Dictionary(uniqueKeysWithValues: remoteDocuments.compactMap { document in
            (document.data()["updatedAt"] as? Timestamp).map { (document.documentID, $0.dateValue()) }
        })
        for item in try localItems(for: list) {
            if deletingListIDs.contains(id) { return }
            if let remoteDate = remoteDates[item.id.uuidString], remoteDate >= item.updatedAt { continue }
            guard user?.uid == uid, !list.isDeleted, !list.firebaseAccessRevoked else {
                throw sharingError("Sign in again to continue.")
            }
            let reference = collection.document(item.id.uuidString)
            let modified = item.updatedAt
            let data: [String: Any] = [
                "name": item.name, "amount": item.amount, "isBought": item.isBought,
                "createdAt": Timestamp(date: item.createdAt), "updatedAt": Timestamp(date: modified),
                "deletedAt": item.deletedAt.map { Timestamp(date: $0) } as Any? ?? NSNull()
            ]
            _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
                do {
                    let remote = try transaction.getDocument(reference)
                    if let date = remote.data()?["updatedAt"] as? Timestamp,
                       date.dateValue() >= modified { return nil }
                    transaction.setData(data, forDocument: reference)
                } catch { errorPointer?.pointee = error as NSError }
                return nil
            }
        }
    }



    func deleteAccount(password: String) async throws {
        guard let user, let email = user.email else { return }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        _ = try await user.reauthenticate(with: credential)
        if user.isEmailVerified {
            let documents = try await Firestore.firestore().collection("shoppingLists")
                .whereField("memberEmails", arrayContains: email.lowercased()).getDocuments(source: .server)
            for document in documents.documents {
                if document.data()["ownerID"] as? String == user.uid {
                    try await purgeList(document.reference)
                } else {
                    try await document.reference.updateData(["memberEmails": FieldValue.arrayRemove([email.lowercased()])])
                }
            }
        }
        try await user.delete()
        if let context {
            let lists = try context.fetch(FetchDescriptor<ShoppingListEntry>())
                .filter { $0.firebaseAccountID == user.uid }
            let ids = Set(lists.map(\.id))
            for item in try context.fetch(FetchDescriptor<ShopItem>())
                where item.listID.map(ids.contains) == true {
                context.delete(item)
            }
            for list in lists { context.delete(list) }
            try context.save()
        }
        updateSession(nil)
    }

    private func sharingError(_ key: String.LocalizationValue) -> NSError {
        NSError(domain: "ShoppingListSharing", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: key)])
    }
}
