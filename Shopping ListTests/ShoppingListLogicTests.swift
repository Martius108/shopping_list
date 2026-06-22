import XCTest
@testable import Shopping_List

final class ShoppingListLogicTests: XCTestCase {
    func testDisplayNameTrimsWhitespaceAndCollapsesSpaces() {
        XCTAssertEqual(
            ShoppingListLogic.displayName(for: "  milk   chocolate  "),
            "Milk chocolate"
        )
    }

    func testMatchesIgnoresCaseAndOuterWhitespace() {
        XCTAssertTrue(ShoppingListLogic.matches(" Milk ", "milk"))
        XCTAssertTrue(ShoppingListLogic.matches("MILK", "milk"))
        XCTAssertFalse(ShoppingListLogic.matches("Milk", "Oat milk"))
    }

    func testSuggestionsAreUniqueCaseInsensitiveSortedAndLimited() {
        let suggestions = ShoppingListLogic.suggestions(
            for: "mi",
            from: ["Milk", "mineral water", "milk", "Mint", "Miso", "Oat milk", "Bread"],
            limit: 3
        )

        XCTAssertEqual(suggestions, ["Milk", "mineral water", "Mint"])
    }

    func testActiveItemsAreSortedCaseInsensitively() {
        let items = [
            ShopItem(name: "Zucchini", isBought: false),
            ShopItem(name: "Apples", isBought: false),
            ShopItem(name: "Bread", isBought: true)
        ]

        XCTAssertEqual(
            ShoppingListLogic.activeItems(from: items).map(\.name),
            ["Apples", "Zucchini"]
        )
    }

    func testRecentlyBoughtItemsAreNewestFirstAndLimited() {
        let older = ShopItem(
            name: "Older",
            isBought: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ShopItem(
            name: "Newer",
            isBought: true,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let active = ShopItem(
            name: "Active",
            isBought: false,
            createdAt: Date(timeIntervalSince1970: 3)
        )

        XCTAssertEqual(
            ShoppingListLogic.recentlyBoughtItems(from: [older, newer, active], limit: 1).map(\.name),
            ["Newer"]
        )
    }

    func testViewSettingsDefaultsAreConsistentAndClamped() {
        let defaults = ViewSettings()
        let invalid = ViewSettings(themeMode: "neon", elementOpacity: 2)

        XCTAssertEqual(defaults.themeMode, ThemeMode.system.rawValue)
        XCTAssertEqual(defaults.backgroundColor, "#F5E4B5")
        XCTAssertEqual(defaults.elementOpacity, 0.7)
        XCTAssertEqual(invalid.themeMode, ThemeMode.system.rawValue)
        XCTAssertEqual(invalid.elementOpacity, 1)
    }
}
