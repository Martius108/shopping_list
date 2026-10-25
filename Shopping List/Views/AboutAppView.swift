import SwiftUI

struct AboutAppView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Rename lists") {
                    Text("In the Lists tab, press and hold the name of a list you own. Enter the new name and choose Save. Renaming a shared list you own changes its name for all participants. Only the owner can rename a received list.")
                }
                Section("Share lists") {
                    Text("Choose the sharing icon on a list you own. Sign in to your Shopping List account, enter the email address of the recipient and send the prepared invitation using your mail app.\n\nIf the recipient is already signed in with the invited email address, the list appears automatically. If the list is already visible in the app, the invitation email can be ignored. Otherwise, the recipient opens the link and signs in or creates an account with the invited address.\n\nConfirm your email once when creating a new account. An existing verified account remains verified after signing out. Each person uses their own account; passwords are not shared. Sign-in is available with a password or an email link.\n\nYou can also use Apple / iCloud to share with Apple devices.")
                }
                Section("Current list and symbols") {
                    Text("Choose the current list in the Lists tab. The sheet icon identifies a list you own; two people before the name identify a received list. A shared list you own also appears in Other Lists for managing access. Both rows refer to the same list, not a copy. Only the owner can add participants.")
                }
                Section("Stop sharing, leave and delete") {
                    Text("As the owner, use the disconnect icon to stop sharing with others. Your list is kept and remains stored in your account. For a received list, Leave removes only your own access. The trash icon permanently deletes a list you own and its items, including for all participants when the list is shared. Signing out ends your session and does not revoke sharing.")
                }
                Section("Local lists and offline use") {
                    Text("You can use local lists without an app account. With iCloud enabled, lists can also sync through your Apple account. Previously loaded shared lists can be viewed and edited offline; changes sync when you reopen or refresh with internet access. Signing in and managing access require internet access. Data stored only locally without a backup is lost if you delete the app.")
                }
                Section("Adjust the appearance") {
                    Text("System follows the device setting; Light and Dark override it for this app. In Settings, choose a background color or your own photo and adjust opacity to keep backed text and list elements readable.")
                }
                Section("Firebase and your data") {
                    Text("The app uses Google Firebase as an external service provider for accounts, connected lists, invitations and sign-in links. Firebase Authentication processes your email address, sign-in information and technical connection data. This authentication service operates in the United States.\n\nCloud Firestore stores connected list names, items, quantities, purchase status, timestamps, user identifiers and invited email addresses. The list database is located in Frankfurt. Participants can see the email addresses within their shared list.\n\nBackground photos and appearance settings are not uploaded to Firebase. Firebase Analytics is not included in this app. With iCloud sync enabled on iPhone, lists, background photos and appearance settings can also sync through your private Apple account.")
                }
                Section {
                    Link("Google Firebase privacy information", destination: URL(string: "https://firebase.google.com/support/privacy")!)
                    Text("Shopping List by Martin Lanius").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About this app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
