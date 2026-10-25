import Foundation
import XCTest
@testable import Shopping_List

final class ShoppingListInvitationTests: XCTestCase {
    func testSharedLinkFormatPreservesUnicodeAndEmailAliases() throws {
        let invitation = try ShoppingListInvitation(listID: "abc_123-XYZ", listName: "Milch & 🍎", email: "friend+family@example.test")
        let fixture = "https://shoppinglist-6c6f4.web.app/invite/#list=abc_123-XYZ&name=Milch%20%26%20%F0%9F%8D%8E&email=friend%2Bfamily%40example.test"
        XCTAssertEqual(invitation.link.absoluteString, fixture)
        let decoded = try ShoppingListInvitation(link: fixture)
        XCTAssertEqual(decoded.listID, invitation.listID)
        XCTAssertEqual(decoded.listName, invitation.listName)
        XCTAssertEqual(decoded.email, invitation.email)
        let appLink = "shoppinglist://invite/1?" + fixture.components(separatedBy: "#")[1]
        XCTAssertEqual(try ShoppingListInvitation(link: appLink).email, invitation.email)
    }

    func testUnknownOriginsDuplicateFieldsAndInvalidPayloadsAreRejected() {
        let fixture = "https://shoppinglist-6c6f4.web.app/invite/#list=abc_123-XYZ&name=Milch%20%26%20%F0%9F%8D%8E&email=friend%2Bfamily%40example.test"
        let invalid = [
            fixture.replacingOccurrences(of: "shoppinglist-6c6f4.web.app", with: "example.test"),
            fixture.replacingOccurrences(of: "https://", with: "http://"),
            fixture.replacingOccurrences(of: "/invite/", with: "/other/"),
            fixture.replacingOccurrences(of: ".web.app/", with: ".web.app:443/"),
            fixture.replacingOccurrences(of: "https://", with: "https://user@"),
            fixture + "&list=other",
            fixture.replacingOccurrences(of: "abc_123-XYZ", with: "bad%2Fpath"),
            fixture.replacingOccurrences(of: "Milch%20", with: "%0AMilch%20"),
            fixture.replacingOccurrences(of: "%40", with: "%20"),
            fixture.replacingOccurrences(of: "abc_123-XYZ", with: "%ZZ"),
            fixture + String(repeating: "x", count: 16384)
        ]
        for value in invalid { XCTAssertThrowsError(try ShoppingListInvitation(link: value)) }
    }
    func testInvitationMailUsesTheAppDisplayNameAndPreservesItsLink() throws {
        let invitation = try ShoppingListInvitation(listID: "abc_123-XYZ", listName: "Milch & 🍎", email: "friend+family@example.test")
        let mail = URLComponents(url: invitation.mailURL, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(mail.scheme, "mailto")
        XCTAssertEqual(mail.path, invitation.email)
        let subject = mail.queryItems!.first { $0.name == "subject" }!.value!
        let body = mail.queryItems!.first { $0.name == "body" }!.value!
        XCTAssertFalse(subject.contains("ShoppingList"))
        XCTAssertFalse(body.contains("ShoppingList"))
        XCTAssertTrue(subject.contains(String(localized: "Shopping List")))
        XCTAssertTrue(body.contains(invitation.listName))
        XCTAssertTrue(body.contains(invitation.link.absoluteString))
        XCTAssertTrue(body.contains(invitation.email))
    }

}
