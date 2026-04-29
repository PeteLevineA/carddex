import XCTest
@testable import CarddexScanner

final class OCRParserTests: XCTestCase {

    func testParsesCollectorNumber() {
        let text = """
        Charmander
        HP 70
        Illus. Naoyo Kimura
        4/165
        MEW 151
        """
        let parsed = OCRParser.parse(text)
        XCTAssertEqual(parsed.number, "4")
        XCTAssertEqual(parsed.printedTotal, 165)
        XCTAssertEqual(parsed.hp, 70)
        XCTAssertEqual(parsed.name, "Charmander")
        XCTAssertEqual(parsed.artist, "Naoyo Kimura")
        XCTAssertEqual(parsed.setHint, "MEW")
    }

    func testHandlesPaddedCollectorMarker() {
        let parsed = OCRParser.parse("Pikachu\nHP 60\n025 / 165")
        XCTAssertEqual(parsed.number, "025")
        XCTAssertEqual(parsed.printedTotal, 165)
    }

    func testReturnsEmptyParsedForGarbage() {
        let parsed = OCRParser.parse("???\n\n")
        XCTAssertNil(parsed.number)
        XCTAssertNil(parsed.hp)
    }
}
