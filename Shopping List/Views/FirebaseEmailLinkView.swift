import SwiftUI

struct FirebaseEmailLinkView: View {
    @EnvironmentObject private var firebase: FirebaseShoppingListManager
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the email address for which you requested this sign-in link.")
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Sign in") {
                        Task {
                            do { try await firebase.completeEmailSignIn(email) }
                            catch { firebase.alertMessage = String(localized: "This sign-in link could not be used. Request a new link.") }
                        }
                    }.disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if firebase.emailLinkInProgress { Section { ProgressView("Please wait…") } }
            }
            .disabled(firebase.emailLinkInProgress)
            .navigationTitle("Sign in without a password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { firebase.closeEmailSignIn() }.disabled(firebase.emailLinkInProgress)
                }
            }
        }
    }
}
