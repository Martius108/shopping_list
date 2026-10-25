import Foundation

// This link identifies the list; verified Firestore membership still controls access.
struct ShoppingListInvitation: Identifiable {
    let listID: String
    let listName: String
    let email: String
    var id: String { listID + ":" + email }

    init(listID: String, listName: String, email: String) throws {
        guard listID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
              !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, listName.utf16.count <= 1000,
              listName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              email.count <= 254,
              email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            throw Self.invalid()
        }
        self.listID = listID
        self.listName = listName
        self.email = email
    }

    init(link: String) throws {
        guard link.utf8.count <= 16384,
              link.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
              let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.user == nil, components.password == nil, components.port == nil else { throw Self.invalid() }
        let query: String?
        if components.scheme == "https", components.host == "shoppinglist-6c6f4.web.app",
           components.path == "/invite/", components.query == nil {
            query = components.percentEncodedFragment
        } else if components.scheme == "shoppinglist", components.host == "invite",
                  components.path == "/1", components.fragment == nil {
            query = components.percentEncodedQuery
        } else { throw Self.invalid() }
        guard let query,
              query.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
              let items = URLComponents(string: "shoppinglist://invite/1?" + query)?.queryItems,
              items.count == 3, Set(items.map(\.name)) == Set(["list", "name", "email"]),
              let listID = items.first(where: { $0.name == "list" })?.value,
              let name = items.first(where: { $0.name == "name" })?.value,
              let email = items.first(where: { $0.name == "email" })?.value else { throw Self.invalid() }
        try self.init(listID: listID, listName: name, email: email)
    }

    var link: URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = [("list", listID), ("name", listName), ("email", email)].map {
            $0.0 + "=" + $0.1.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return URL(string: "https://shoppinglist-6c6f4.web.app/invite/#" + query)!
    }

    var mailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(format: String(localized: "Shopping List: invitation to %@"), listName)),
            URLQueryItem(name: "body", value: String(format: String(localized: "You have been invited to Shopping List: %@.\n\nIf this list is already visible in your app, no further action is needed and you can ignore this email. Otherwise, open this link on your phone:\n%@\n\nSign in with %@, or create a Shopping List account with this email and a password. If you create a new account, confirm your email once and return to the app. The list appears automatically."), listName, link.absoluteString, email))
        ]
        return components.url!
    }

    private static func invalid() -> NSError {
        NSError(domain: "ShoppingListInvitation", code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "This invitation is invalid. Ask the sender for a new invitation.")])
    }
}
