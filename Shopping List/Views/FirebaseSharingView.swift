import FirebaseAuth
import SwiftUI

struct FirebaseSharingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    let invitation: ShoppingListInvitation?
    private let close: (() -> Void)?
    @EnvironmentObject private var firebase: FirebaseShoppingListManager
    @AppStorage("pendingFirebaseSharingListID") private var pendingSharingID = ""
    @State private var list: ShoppingListEntry?
    @State private var email = ""
    @State private var password = ""
    @State private var recipient = ""
    @State private var isCreatingAccount = false
    @State private var isWorking = false
    @State private var workingMessage = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isDeletingAccount = false
    @State private var deletionPassword = ""
    @State private var memberToRemove: String?
    @FocusState private var isEditing: Bool

    init(list: ShoppingListEntry?, invitation: ShoppingListInvitation? = nil, close: (() -> Void)? = nil) {
        _list = State(initialValue: list)
        _email = State(initialValue: invitation?.email ?? "")
        self.invitation = invitation
        self.close = close
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            Form {
                if let invitation {
                    Section("Invitation") {
                        Text(invitation.listName).font(.headline)
                        Text(invitation.email)
                        Text("Sign in or create a ShoppingList account with the invited email. After email confirmation, the list opens automatically.")
                    }
                }
                if let message {
                    Section { Label(message, systemImage: "info.circle") }.id("feedback")
                }
                if let list {
                    Section("Selected List") {
                        Text(list.name).font(.headline)
                        if !list.firebaseSharingReady { Text("This list has not been shared yet.") }
                    }
                }
                if let user = firebase.user {
                    Section("ShoppingList account") {
                        Text(user.email ?? "")
                        if let invitation, user.email?.lowercased() != invitation.email.lowercased() {
                            Text("Sign out and sign in with the email address shown in this invitation.")
                            Button("Sign out") { perform { try firebase.signOut() } }
                        }
                        if !user.isEmailVerified {
                            Text("Open the link in the confirmation email, then return here. Sharing continues in this dialog.")
                            Button("Send verification email") {
                                perform {
                                    try await user.sendEmailVerification()
                                    message = String(localized: "Verification email sent.")
                                }
                            }
                            Button("I have confirmed my email") {
                                perform {
                                    try await firebase.refreshSession()
                                    if firebase.user?.isEmailVerified == false {
                                        message = String(localized: "Your email is not confirmed yet. Open the link in the email, then return here.")
                                    }
                                }
                            }
                        } else {
                            Label("Email address confirmed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }

                    if user.isEmailVerified {
                        if let list {
                            if list.firebaseListID == nil || list.firebaseOwnerID == user.uid {
                                Section("Share list") {
                                    Text("Enter the recipient’s email address. On your own other device, use the same ShoppingList account.")
                                    if list.sharedZoneName != nil && list.firebaseListID == nil {
                                        Text("A separate shared copy will be created for this group.")
                                    }
                                    TextField("Recipient email address", text: $recipient)
                                        .keyboardType(.emailAddress)
                                        .textContentType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .focused($isEditing)
                                    Button("Grant Access") {
                                        perform("Sharing your list… Please wait.") {
                                            let target = try await firebase.grantAccess(to: recipient, list: list)
                                            self.list = target
                                            if pendingSharingID == list.id.uuidString { pendingSharingID = "" }
                                            try sendInvitation(for: target, email: recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                                            recipient = ""
                                        }
                                    }
                                    .disabled(recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }

                            if let id = list.firebaseListID {
                                Section("People with access") {
                                    ForEach(firebase.members[id] ?? [], id: \.self) { member in
                                        HStack {
                                            Text(member)
                                                .lineLimit(2)
                                            Spacer()
                                            if list.firebaseOwnerID == user.uid && member != user.email?.lowercased() {
                                                Button { perform { try sendInvitation(for: list, email: member) } } label: {
                                                    Image(systemName: "envelope")
                                                }.accessibilityLabel("Send invitation")
                                                Button(role: .destructive) { memberToRemove = member } label: {
                                                    Image(systemName: "person.crop.circle.badge.minus")
                                                }
                                                .accessibilityLabel("Remove access")
                                            }
                                        }
                                    }
                                }
                            }
                        } else if invitation != nil {
                            if user.email?.lowercased() == invitation?.email.lowercased() {
                                Button("Open list") { perform("Opening the shared list…") { try await firebase.openInvitation() } }
                            }
                        } else {
                            Section { Text("Lists shared with your confirmed email address appear automatically in the Lists tab.") }
                        }
                    }

                    if list == nil && invitation == nil {
                    Section {
                        Button("Set or change password") {
                            perform {
                                try await Auth.auth().sendPasswordReset(withEmail: user.email ?? "")
                                message = String(localized: "If an account exists for this address, you will receive a password reset email.")
                            }
                        }
                        Button("Sign out") {
                            perform { try firebase.signOut() }
                        }
                        Button("Delete ShoppingList account", role: .destructive) {
                            deletionPassword = ""
                            isDeletingAccount = true
                        }
                    }
                    }
                } else {
                    Section {
                        Text("Sign in to share lists with other people on Android and iPhone.")
                        Text("An existing ShoppingList account works on all your devices. Use the same email and ShoppingList password.")
                        Toggle("Create a new account", isOn: $isCreatingAccount)
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEditing)
                        if !isCreatingAccount {
                            Button("Sign in by email link — no password") {
                                perform {
                                    try await firebase.sendEmailSignInLink(email)
                                    message = String(localized: "Sign-in link sent. Open this email on this device to sign in without copying your password.")
                                }
                            }.disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        SecureField("Password", text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .focused($isEditing)
                        Button(isCreatingAccount ? "Create account" : "Sign in") {
                            perform {
                                let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                if isCreatingAccount {
                                    let result: AuthDataResult
                                    do { result = try await Auth.auth().createUser(withEmail: email, password: password) }
                                    catch where (error as NSError).code == AuthErrorCode.emailAlreadyInUse.rawValue {
                                        isCreatingAccount = false
                                        message = String(localized: "This email already has a ShoppingList account. Sign in with its existing password, or choose Reset password.")
                                        return
                                    }
                                    password = ""
                                    do {
                                        try await result.user.sendEmailVerification()
                                        message = String(localized: "Account created. Open the link in your email, then return here to continue.")
                                    } catch {
                                        message = String(localized: "Your account exists, but email delivery could not be confirmed. You can resend the confirmation email here.")
                                        throw error
                                    }
                                } else {
                                    _ = try await Auth.auth().signIn(withEmail: email, password: password)
                                    password = ""
                                }
                            }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || password.isEmpty
                                  || (isCreatingAccount && password.count < 6))
                        Button("Reset password") {
                            perform {
                                try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
                                message = String(localized: "If an account exists for this address, you will receive a password reset email.")
                            }
                        }
                        .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .disabled(isWorking || firebase.emailLinkInProgress)
            .overlay {
                if isWorking || firebase.emailLinkInProgress {
                    VStack(spacing: 12) { ProgressView(); Text(firebase.emailLinkInProgress ? String(localized: "Please wait…") : workingMessage).multilineTextAlignment(.center) }
                        .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding().accessibilityAddTraits(.updatesFrequently)
                }
            }
            .onChange(of: message) { _, value in
                if value != nil { withAnimation { scroll.scrollTo("feedback", anchor: .top) } }
            }
            .onChange(of: firebase.user?.isEmailVerified) { _, confirmed in
                if confirmed == true { message = String(localized: "Email address confirmed") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(invitation != nil ? Text("Invitation") : list == nil ? Text("ShoppingList account") : Text("Share list"))
            .task(id: (firebase.user?.uid ?? "") + String(firebase.user?.isEmailVerified ?? false)) {
                if let invitation, let user = firebase.user, user.isEmailVerified,
                   user.email?.lowercased() == invitation.email.lowercased() {
                    perform("Opening the shared list…") { try await firebase.openInvitation() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && firebase.user?.isEmailVerified == false {
                    Task { try? await firebase.refreshSession() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(list != nil && pendingSharingID == list?.id.uuidString ? "Later" : "Done") {
                        if let close { close() } else { dismiss() }
                    }.disabled(isWorking || firebase.emailLinkInProgress)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditing = false }
                }
            }
            .alert("Action could not be completed", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .alert("Delete ShoppingList account", isPresented: $isDeletingAccount) {
                SecureField("Password", text: $deletionPassword)
                Button("Cancel", role: .cancel) { deletionPassword = "" }
                Button("Delete account", role: .destructive) {
                    perform {
                        defer { deletionPassword = "" }
                        try await firebase.deleteAccount(password: deletionPassword)
                    }
                }
            } message: {
                Text("Your shared lists will be deleted for all participants. Enter your password to confirm.")
            }
            .confirmationDialog("Remove access", isPresented: Binding(
                get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }
            )) {
                if let memberToRemove, let list {
                    Button("Remove access", role: .destructive) {
                        perform { try await firebase.removeMember(memberToRemove, from: list) }
                    }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            }
            }
        }
    }

    private func sendInvitation(for list: ShoppingListEntry, email: String) throws {
        guard list.firebaseSharingReady, let id = list.firebaseListID else { return }
        let invitation = try ShoppingListInvitation(listID: id, listName: list.name, email: email)
        message = String(localized: "Access saved. Send the prepared invitation in your mail app.")
        openURL(invitation.mailURL) { accepted in
            if !accepted { message = String(localized: "No mail app is available. Set up a mail app, then use Send invitation next to the recipient.") }
        }
    }

    private func perform(_ status: String.LocalizationValue = "Please wait…", _ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        workingMessage = String(localized: status)
        isEditing = false
        isWorking = true
        message = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                if firebase.receivedInvitation != nil, let invitation,
                   let user = Auth.auth().currentUser, user.isEmailVerified,
                   user.email?.lowercased() == invitation.email.lowercased() {
                    try await firebase.refreshSession()
                    try await firebase.openInvitation()
                }
            }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
