import XCTest
@testable import EyeLine

@MainActor
final class ScriptMatchingServiceTests: XCTestCase {

    private func makeService() -> ScriptMatchingService {
        ScriptMatchingService()
    }

    func testExactMatchAdvancesToEnd() {
        let service = makeService()
        service.loadScript("I went to the store to buy some food.")
        let result = service.processRecognizedText("I went to the store to buy some food.")
        XCTAssertEqual(result, 8)
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testSkippedWordStillTracksToEnd() {
        let service = makeService()
        service.loadScript("I went to the store to buy some food.")
        service.processRecognizedText("I went to store to buy some food.")
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testFillerWordIsIgnored() {
        let service = makeService()
        service.loadScript("I went to the store to buy some food.")
        service.processRecognizedText("I went uh to the store to buy some food.")
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testMisrecognizedWordDoesNotBreakTracking() {
        let service = makeService()
        service.loadScript("I went to the store to buy some food.")
        service.processRecognizedText("I went to the storm to buy some food.")
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testRepeatedPhraseStaysNearCurrentPosition() {
        let service = makeService()
        service.loadScript("Today we're going to talk about business. Later we're going to talk about business growth.")
        // Simulate having just matched "Today" (index 0).
        service.manuallySetPosition(to: 0)
        service.processRecognizedText("we're going to talk about business")
        // Should land on the FIRST "business" (index 6), not the second (index 13).
        XCTAssertEqual(service.currentIndex, 6)
    }

    func testSelfCorrectionRecoversToIntendedPhrase() {
        let service = makeService()
        service.loadScript("Today I want to talk about work.")
        service.processRecognizedText("Today I went today I want to talk about work")
        XCTAssertEqual(service.currentIndex, 6) // "work", the end of the script
    }

    func testRepeatedWordDoesNotCauseIncorrectBackwardMove() {
        let service = makeService()
        service.loadScript("I want to talk about this.")
        service.processRecognizedText("I want to, I want to talk about this.")
        XCTAssertEqual(service.currentIndex, 5) // "this", the end
    }

    func testForwardRecoveryAfterSkippingAnEntireSentence() {
        let service = makeService()
        service.loadScript("Alpha bravo charlie delta echo. Foxtrot golf hotel india juliet kilo lima.")
        service.processRecognizedText("foxtrot golf hotel india juliet kilo lima")
        XCTAssertEqual(service.currentIndex, 11) // "lima", end of the second sentence
    }

    func testLargeBackwardJumpIsRejected() {
        let service = makeService()
        service.loadScript("one two three four five six seven eight nine ten eleven twelve")
        service.manuallySetPosition(to: 11) // simulate having reached the end
        let result = service.processRecognizedText("one two three")
        XCTAssertNil(result)
        XCTAssertEqual(service.currentIndex, 11) // unchanged
    }

    func testEmptyRecognizedTextDoesNothing() {
        let service = makeService()
        service.loadScript("I went to the store to buy some food.")
        service.manuallySetPosition(to: 8)
        let result = service.processRecognizedText("")
        XCTAssertNil(result)
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testManualRepositionRecentersSearchWindow() {
        let service = makeService()
        service.loadScript("one two three four five six seven eight nine ten eleven twelve")
        service.manuallySetPosition(to: 5)
        XCTAssertEqual(service.currentIndex, 5)
        service.processRecognizedText("seven eight nine")
        XCTAssertEqual(service.currentIndex, 8)
    }

    func testTokenizeNormalizesPunctuationAndContractions() {
        let tokens = ScriptMatchingService.tokenize("Don't stop—believe! It's amazing.")
        let normalized = tokens.map(\.normalized)
        XCTAssertEqual(normalized, ["dont", "stop", "believe", "its", "amazing"])
    }
}
