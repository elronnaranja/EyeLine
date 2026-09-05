import Foundation

/// A single normalized word from the script, keyed to its position in the
/// original text so the UI can later render completed/current/upcoming
/// spans without re-parsing the script on every update.
struct ScriptToken: Equatable {
    let index: Int
    let normalized: String
    let range: Range<String.Index>
}

/// Tracks the speaker's current position in a script by aligning short
/// windows of live speech-recognition text against a local neighborhood of
/// script tokens, instead of comparing the full transcript to the full
/// script on every update (which would both be slow for long scripts and
/// prone to snapping to the wrong occurrence of a repeated phrase).
///
/// The alignment itself is a local sequence alignment (Smith-Waterman
/// style): it scores runs of consecutive matching words much more highly
/// than isolated matches, treats a skipped or misheard word as a small gap
/// rather than a broken match, and lets a bad partial alignment (e.g. a
/// false start the speaker corrects) fall back to zero and restart from a
/// better-scoring run later in the same speech window. Forward and backward
/// jumps away from the current position both require a raw match score that
/// scales with distance, and among near-tied candidates the one closer to
/// the current position wins — this is what keeps a repeated phrase
/// elsewhere in the script from stealing position with only ordinary
/// evidence.
///
/// Deliberately independent of SpeechRecognitionService and SwiftUI so it
/// can be unit tested in isolation.
@MainActor
final class ScriptMatchingService {

    private(set) var tokens: [ScriptToken] = []
    private(set) var currentIndex: Int = -1 // -1 = nothing matched yet

    private let backwardWindow: Int
    private let forwardWindow: Int
    private let tailWordCount: Int
    private let maxBackwardJump: Int
    private let maxForwardJump: Int

    static let fillerWords: Set<String> = ["uh", "um", "erm", "ah", "hmm", "uhh", "umm", "mm", "mhm"]

    private static let lowWeightWords: Set<String> = [
        "the", "a", "an", "to", "and", "is", "of", "in", "it", "that", "for", "on",
        "are", "was", "with", "as", "be", "this", "have", "or", "at", "but", "not",
        "we", "he", "she", "they", "my", "your", "his", "her", "its", "our", "their",
        "do", "did", "does", "so", "if", "just", "then", "than", "there", "here",
        "what", "who", "how", "im", "youre", "were", "ive", "id", "ill"
    ]

    init(
        backwardWindow: Int = 20,
        forwardWindow: Int = 30,
        tailWordCount: Int = 14,
        maxBackwardJump: Int = 6,
        maxForwardJump: Int = 20
    ) {
        self.backwardWindow = backwardWindow
        self.forwardWindow = forwardWindow
        self.tailWordCount = tailWordCount
        self.maxBackwardJump = maxBackwardJump
        self.maxForwardJump = maxForwardJump
    }

    func loadScript(_ text: String) {
        tokens = Self.tokenize(text)
        currentIndex = -1
    }

    func reset() {
        currentIndex = -1
    }

    /// For manual swipe-to-reposition: jumps straight to a token index. The
    /// next processRecognizedText call searches around this new position.
    func manuallySetPosition(to index: Int) {
        currentIndex = max(-1, min(index, tokens.count - 1))
    }

    /// Feed the latest recognized text for the current utterance (partial
    /// results are expected to keep growing the same utterance — this
    /// always looks at the tail end of whatever is passed in). Returns the
    /// new current index if position advanced/moved with enough confidence,
    /// or nil if nothing changed.
    @discardableResult
    func processRecognizedText(_ text: String) -> Int? {
        guard !tokens.isEmpty else { return nil }

        let speechWords = Self.normalizeAndTokenize(text).filter { !Self.fillerWords.contains($0) }
        guard !speechWords.isEmpty else { return nil }
        let tail = Array(speechWords.suffix(tailWordCount))

        let searchStart = max(0, currentIndex - backwardWindow)
        let searchEnd = min(tokens.count - 1, max(currentIndex, 0) + forwardWindow)
        guard searchStart <= searchEnd else { return nil }

        guard let match = Self.bestAlignment(
            speechTail: tail,
            scriptTokens: tokens,
            searchRange: searchStart...searchEnd,
            currentIndex: currentIndex
        ) else { return nil }

        let jump = match.endIndex - currentIndex
        if jump < 0 && -jump > maxBackwardJump { return nil }
        // A hard ceiling independent of score: even a strong-looking match
        // shouldn't be allowed to teleport the reading position dozens of
        // words ahead from a couple of spoken words — that read as the
        // whole screen suddenly scrolling past unspoken text.
        if jump > maxForwardJump { return nil }

        guard match.score >= Self.requiredScore(forJump: jump) else { return nil }

        currentIndex = match.endIndex
        return currentIndex
    }

    // MARK: - Alignment

    private struct AlignmentResult {
        let endIndex: Int
        let score: Double
    }

    private static func bestAlignment(
        speechTail: [String],
        scriptTokens: [ScriptToken],
        searchRange: ClosedRange<Int>,
        currentIndex: Int
    ) -> AlignmentResult? {
        let window = Array(scriptTokens[searchRange])
        guard !window.isEmpty else { return nil }

        let m = speechTail.count
        let n = window.count
        let mismatchPenalty = 0.6
        let gapPenalty = 0.8
        let distanceTiebreak = 0.05

        // H[i][j]: best local-alignment score using speechTail[0..<i] and window[0..<j].
        var H = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: m + 1)
        var bestScore = 0.0
        var bestAdjusted = -Double.greatestFiniteMagnitude
        var bestJ = 0

        for i in 1...m {
            for j in 1...n {
                let matches = speechTail[i - 1] == window[j - 1].normalized
                let substitution = matches ? weight(for: window[j - 1].normalized) : -mismatchPenalty
                let value = max(
                    0,
                    H[i - 1][j - 1] + substitution,
                    H[i - 1][j] - gapPenalty,
                    H[i][j - 1] - gapPenalty
                )
                H[i][j] = value

                let scriptIndex = searchRange.lowerBound + j - 1
                let distance = Double(abs(scriptIndex - max(currentIndex, searchRange.lowerBound)))
                let adjusted = value - distanceTiebreak * distance
                if adjusted > bestAdjusted {
                    bestAdjusted = adjusted
                    bestScore = value
                    bestJ = j
                }
            }
        }

        guard bestScore > 0, bestJ > 0 else { return nil }
        let endIndex = searchRange.lowerBound + bestJ - 1
        return AlignmentResult(endIndex: endIndex, score: bestScore)
    }

    /// Larger jumps (forward or backward) need a proportionally stronger
    /// run of matching words — this is what stops a single common word
    /// echoed near a repeated phrase from teleporting the position there.
    private static func requiredScore(forJump jump: Int) -> Double {
        1.6 + Double(abs(jump)) * 0.09
    }

    private static func weight(for word: String) -> Double {
        if lowWeightWords.contains(word) || word.count <= 2 {
            return 0.4
        }
        return 1.0
    }

    // MARK: - Tokenization

    static func tokenize(_ script: String) -> [ScriptToken] {
        var result: [ScriptToken] = []
        var index = 0
        script.enumerateSubstrings(in: script.startIndex..<script.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring else { return }
            let normalized = normalize(substring)
            guard !normalized.isEmpty else { return }
            result.append(ScriptToken(index: index, normalized: normalized, range: range))
            index += 1
        }
        return result
    }

    static func normalizeAndTokenize(_ text: String) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { substring, _, _, _ in
            guard let substring else { return }
            let normalized = normalize(substring)
            if !normalized.isEmpty { words.append(normalized) }
        }
        return words
    }

    /// Lowercases and strips punctuation (including apostrophes), so
    /// "Don't" and "dont" — the kind of variation speech recognition
    /// produces — normalize identically.
    static func normalize(_ word: String) -> String {
        let lowered = word.lowercased()
        let filtered = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }
}
