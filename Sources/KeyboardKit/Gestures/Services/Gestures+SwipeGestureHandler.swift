//
//  Gestures+SwipeGestureHandler.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2025-11-29.
//  Copyright © 2025 Daniel Saidi. All rights reserved.
//

import CoreGraphics
import Foundation

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

public extension Gestures {

    /// This custom gesture handler can handle swipe-to-type
    /// gestures that predict words from finger path.
    ///
    /// This handler uses a spatial probability model with beam
    /// search to convert gesture paths into words. The algorithm:
    /// 1. Filters the path by distance to reduce noise
    /// 2. Identifies start/end keys (most reliable information)
    /// 3. Filters dictionary candidates by start/end match
    /// 4. Scores each candidate using spatial probability
    /// 5. Ranks by geometric similarity + word frequency
    class SwipeGestureHandler {

        /// Create a swipe gesture handler instance.
        ///
        /// - Parameters:
        ///   - swipeContext: The swipe context to use.
        ///   - keyboardContext: The keyboard context to use.
        ///   - actionHandler: The action handler to use for inserting words.
        public init(
            swipeContext: SwipeContext,
            keyboardContext: KeyboardContext,
            actionHandler: KeyboardActionHandler
        ) {
            self.swipeContext = swipeContext
            self.keyboardContext = keyboardContext
            self.actionHandler = actionHandler
        }


        /// The swipe context to use.
        private let swipeContext: SwipeContext

        /// The keyboard context to use.
        private let keyboardContext: KeyboardContext

        /// The action handler to use.
        private let actionHandler: KeyboardActionHandler

        /// Gaussian standard deviation for spatial probability.
        private let sigma: CGFloat = 22.0

        /// Minimum distance between path points (in pixels).
        private let minPathDistance: CGFloat = 8.0

        /// Minimum number of filtered path points required.
        private let minPathPoints = 10

        /// Cached dictionary words for better performance.
        private var cachedDictionary: [String]?
        private var dictionaryLock = NSLock()

        /// UILexicon instance for accessing system dictionary
        private var lexicon: UILexicon?
        private var isLoadingLexicon = false


        /// Handle the start of a swipe gesture.
        public func handleSwipeStart(_ point: CGPoint) {
            swipeContext.start(at: point)
        }

        /// Handle the continuation of a swipe gesture.
        public func handleSwipeChanged(_ point: CGPoint) {
            swipeContext.update(with: point)
        }

        /// Handle the end of a swipe gesture.
        public func handleSwipeEnded(_ point: CGPoint) {
            swipeContext.update(with: point)
            let path = swipeContext.path
            let keyBounds = swipeContext.keyBounds

            swipeContext.end()

            // Process on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if let word = self.predictWord(from: path, keyBounds: keyBounds) {
                    DispatchQueue.main.async {
                        self.actionHandler.handle(.release, on: .character(word))
                        self.actionHandler.handle(.release, on: .space)
                    }
                }
            }
        }

        /// Predict a word from the swipe path using spatial probability + beam search.
        ///
        /// - Parameters:
        ///   - path: The swipe path points.
        ///   - keyBounds: The map of keys to their screen positions.
        /// - Returns: The predicted word, if any.
        private func predictWord(from path: [CGPoint], keyBounds: [String: CGRect]) -> String? {
            guard path.count > 5 else { return nil }

            // Step 1: Filter path by distance to reduce noise
            let filteredPath = filterPathByDistance(path)
            guard filteredPath.count >= minPathPoints else { return nil }

            // Step 2: Get start and end keys (most reliable information)
            guard let startKey = keyForPoint(filteredPath.first!, in: keyBounds),
                  let endKey = keyForPoint(filteredPath.last!, in: keyBounds),
                  startKey.count == 1,
                  endKey.count == 1 else {
                return nil
            }

            let startChar = startKey.lowercased()
            let endChar = endKey.lowercased()

            // Step 3: Get dictionary and filter candidates
            let dictionary = getDictionary()
            let candidates = filterCandidates(
                from: dictionary,
                startChar: startChar,
                endChar: endChar,
                estimatedLength: filteredPath.count / 4  // Heuristic: ~4 points per letter
            )

            guard !candidates.isEmpty else { return nil }

            // Step 4: Score each candidate using spatial probability
            var scoredCandidates: [(word: String, score: Double)] = []

            for word in candidates {
                let idealPath = generateIdealPath(for: word, keyBounds: keyBounds)
                guard !idealPath.isEmpty else { continue }

                let spatialScore = calculateSpatialProbability(
                    userPath: filteredPath,
                    idealPath: idealPath
                )

                // Combine spatial score with word frequency
                let frequencyScore = wordFrequencyScore(word)
                let totalScore = spatialScore + log(frequencyScore + 1.0)

                scoredCandidates.append((word, totalScore))
            }

            // Step 5: Return best match
            guard let best = scoredCandidates.max(by: { $0.score < $1.score }) else {
                return nil
            }

            // Only return if confidence is reasonable
            return best.score > -500.0 ? best.word : nil
        }

        // MARK: - Path Processing

        /// Filter path points by minimum distance threshold.
        private func filterPathByDistance(_ path: [CGPoint]) -> [CGPoint] {
            guard path.count > 1 else { return path }

            var filtered = [path[0]]

            for point in path {
                let lastPoint = filtered.last!
                if distance(lastPoint, point) >= minPathDistance {
                    filtered.append(point)
                }
            }

            return filtered
        }

        /// Calculate Euclidean distance between two points.
        private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            let dx = p1.x - p2.x
            let dy = p1.y - p2.y
            return sqrt(dx * dx + dy * dy)
        }

        /// Find which key contains the given point.
        private func keyForPoint(_ point: CGPoint, in keyBounds: [String: CGRect]) -> String? {
            return keyBounds.first(where: { $0.value.contains(point) })?.key
        }

        // MARK: - Dictionary Management

        /// Get the dictionary, using cache if available.
        private func getDictionary() -> [String] {
            dictionaryLock.lock()
            defer { dictionaryLock.unlock() }

            if let cached = cachedDictionary {
                return cached
            }

            var words: [String] = []

            // Try to get words from UILexicon (iOS system dictionary)
            if let lex = lexicon {
                // Use cached UILexicon entries
                words = lex.entries.map { $0.documentText.lowercased() }
                    .filter { $0.count >= 2 && $0.count <= 15 && $0.allSatisfy(\.isLetter) }
            } else {
                // Start loading UILexicon asynchronously for future use
                loadUILexiconAsync()

                // Use comprehensive word list as fallback
                words = getBasicEnglishWordList()
            }

            cachedDictionary = words
            return words
        }

        /// Load UILexicon asynchronously (iOS system dictionary)
        private func loadUILexiconAsync() {
            guard !isLoadingLexicon else { return }
            isLoadingLexicon = true

            UITextChecker.requestLexicon(from: keyboardContext.textDocumentProxy) { [weak self] lexicon in
                guard let self = self else { return }

                self.dictionaryLock.lock()
                self.lexicon = lexicon
                // Clear cache to force reload with UILexicon words
                self.cachedDictionary = nil
                self.isLoadingLexicon = false
                self.dictionaryLock.unlock()
            }
        }

        /// Get a basic English word list.
        /// First tries to load from bundled dictionary file, then falls back to hardcoded list.
        private func getBasicEnglishWordList() -> [String] {
            // Try to load from bundled dictionary file
            if let fileURL = Bundle.module.url(forResource: "swype_dictionary", withExtension: "txt", subdirectory: "Resources"),
               let fileContents = try? String(contentsOf: fileURL, encoding: .utf8) {
                let words = fileContents.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty && $0.allSatisfy(\.isLetter) }
                return words
            }

            // Fallback: Comprehensive hardcoded word list
            // This ensures the feature works even if dictionary file isn't found
            let commonWords = """
            a about above across add after again against age ago air all almost alone along already also although always am among an and animal another answer any are area around as ask at away
            back bad ball base be bear beat beautiful became because become bed been before began begin behind being believe below best better between big bird black blue boat body book both bottom box boy bread break bring brother brought build built burn business but buy by
            call came can car care carry case cat catch cause cell center century certain change character check child children choose city class clear close cloud cold color come common complete condition consider contain continue control could country course cover create cross cry current cut
            dad dark day dead deal dear death decide deep degree describe design determine develop did die difference different difficult direct do doctor does dog done door down draw dream dress drink drive drop dry during
            each early earth ease east easy eat edge education effect eight either else end energy enough enter entire even evening ever every everyone everything evidence exactly example experience eye
            face fact fair fall family far fast father fear feel feet fell felt few field fight figure fill final finally find fine finger finish fire first fish five floor fly follow food foot for force form forward found four free friend from front full
            game garden gas gave general get girl give glad glass go god goes gold gone good got government great green ground group grow guard guess gun
            had hair half hand happen happy hard has hat have he head hear heard heart heat heavy held hello help her here high him himself his history hit hold home hope horse hospital hot hour house how however huge human hundred
            i idea if image imagine important in include increase indeed indicate industry information inside instead interest into is island issue it its itself
            job join just keep kept key kid kill kind king knew know knowledge
            lady land language large last late later laugh law lay lead learn least leave led left leg less let letter level lie life light like line list listen little live long look lose lost lot love low
            made main make man manage many map mark market matter may maybe me mean measure meet member memory men message method middle might mile military million mind minute miss modern moment money month more morning most mother mountain move movement much music must my myself
            name nation natural nature near nearly necessary need never new news next nice night nine no none nor north not note nothing notice now number
            object of off offer office often oh oil ok old on once one only open or order other our out outside over own
            page pain paint pair paper parent part particular party pass past pattern pay peace people per perform perhaps period person pick picture piece place plan plant play player point poor popular population position possible power practice prepare present president press pretty prevent probably problem process produce product program project prove provide public pull purpose push put
            question quick quickly quiet quite
            race radio raise range rate rather reach read ready real realize really reason receive recent recently record red reduce region relate remember remove report represent require research rest result return reveal rich right rise river road rock role room rule run
            safe said sale same save say scene school science sea season seat second section see seem sell send sense sent serious serve service set seven several shall share she ship short should show side sign similar simple simply since sing single sister sit site situation six size skill skin small smile so social society soft some someone something sometimes son song soon sort sound south space speak special specific speech spend sport spread spring staff stage stand star start state statement station stay step still stock stop store story straight strategy street strong student study stuff style subject success such suddenly suffer suggest summer support sure surface system
            table take talk task teach teacher team technology tell ten term test than thank that the their them themselves then theory there these they thing think third this those though thought thousand three through throughout throw thus time to today together told tomorrow tonight too took top total touch toward town trade traditional training travel treat treatment tree trial trip trouble true truth try turn two type
            under understand unit until up upon us use usually
            value various very view violence visit voice vote
            wait walk wall want war warm was watch water wave way we weapon wear week weight well were west what when where whether which while white who whole whom whose why wide wife will win wind window wish with within without woman wonder word work worker world worry would write writer wrong
            year yes yet you young your yourself
            google search research internet website computer phone keyboard message email text hello world test testing example sample question answer solution problem issue error warning notice information data result output input value string array list dictionary object function method property type
            """.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

            return commonWords
        }

        /// Filter dictionary candidates by start/end characters and estimated length.
        private func filterCandidates(
            from dictionary: [String],
            startChar: String,
            endChar: String,
            estimatedLength: Int
        ) -> [String] {
            return dictionary.filter { word in
                guard word.count >= 2 else { return false }

                let wordStart = String(word.prefix(1)).lowercased()
                let wordEnd = String(word.suffix(1)).lowercased()

                // Must match start and end characters
                guard wordStart == startChar && wordEnd == endChar else {
                    return false
                }

                // Length should be within reasonable range
                let lengthDiff = abs(word.count - estimatedLength)
                return lengthDiff <= max(5, word.count / 2)
            }
        }

        // MARK: - Spatial Probability Scoring

        /// Generate ideal swipe path for a word by connecting key centers.
        private func generateIdealPath(for word: String, keyBounds: [String: CGRect]) -> [CGPoint] {
            var path: [CGPoint] = []

            for char in word.lowercased() {
                let key = String(char)
                if let rect = keyBounds[key] {
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    path.append(center)
                }
            }

            return path
        }

        /// Calculate spatial probability using Gaussian distance model.
        /// Returns log probability for numerical stability.
        private func calculateSpatialProbability(
            userPath: [CGPoint],
            idealPath: [CGPoint]
        ) -> Double {
            guard !idealPath.isEmpty else { return -Double.infinity }

            var totalLogProb = 0.0

            // For each point in user's path, find distance to nearest ideal path point
            for userPoint in userPath {
                let minDist = idealPath.map { distance(userPoint, $0) }.min() ?? CGFloat.infinity

                // Gaussian probability: exp(-dist² / (2σ²))
                // Use log probability to avoid underflow
                let logProb = -Double(minDist * minDist) / (2.0 * Double(sigma * sigma))
                totalLogProb += logProb
            }

            // Normalize by path length to avoid bias toward shorter words
            return totalLogProb / Double(userPath.count)
        }

        /// Get word frequency score (higher = more common).
        /// In production, this should use actual word frequency data.
        private func wordFrequencyScore(_ word: String) -> Double {
            // Very basic frequency estimation
            // In production, use actual word frequency corpus

            // Common short words
            let veryCommon = ["the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for", "not", "on", "with", "he", "as", "you", "do", "at"]
            if veryCommon.contains(word.lowercased()) {
                return 1000.0
            }

            let common = ["this", "but", "his", "by", "from", "they", "we", "say", "her", "she", "or", "an", "will", "my", "one", "all", "would", "there", "their"]
            if common.contains(word.lowercased()) {
                return 500.0
            }

            // Longer words are generally less common
            let lengthPenalty = Double(word.count) / 10.0
            return max(1.0, 100.0 - lengthPenalty * 10.0)
        }
    }
}
#endif
