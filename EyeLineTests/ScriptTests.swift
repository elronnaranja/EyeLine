import XCTest
@testable import EyeLine

final class ScriptTests: XCTestCase {

    func testPreviewCollapsesWhitespaceAndTruncates() {
        let longLine = String(repeating: "word ", count: 40)
        let script = Script(title: "Test", content: "Line one\nLine two\n" + longLine)
        XCTAssertFalse(script.preview.contains("\n"))
        XCTAssertTrue(script.preview.count <= 121)
    }

    func testDuplicateCopiesContentWithNewIdentity() {
        let original = Script(title: "Original", content: "Hello world")
        let copy = original.duplicate()
        XCTAssertNotEqual(original.id, copy.id)
        XCTAssertEqual(copy.content, original.content)
        XCTAssertEqual(copy.title, "Original Copy")
    }

    func testWordCountIgnoresWhitespace() {
        let script = Script(content: "one  two\nthree")
        XCTAssertEqual(script.wordCount, 3)
    }
}
