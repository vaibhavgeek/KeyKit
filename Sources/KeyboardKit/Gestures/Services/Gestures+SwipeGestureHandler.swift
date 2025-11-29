//
//  Gestures+SwipeGestureHandler.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2025-11-29.
//  Copyright © 2025 Daniel Saidi. All rights reserved.
//

import CoreGraphics

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

public extension Gestures {

    /// This custom gesture handler can handle swipe-to-type
    /// gestures that predict words from finger path.
    ///
    /// This handler uses UITextChecker to convert the noisy
    /// key sequence into predicted words.
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

        /// The text checker for word prediction.
        private let textChecker = UITextChecker()


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

        /// Predict a word from the swipe path.
        ///
        /// - Parameters:
        ///   - path: The swipe path points.
        ///   - keyBounds: The map of keys to their screen positions.
        /// - Returns: The predicted word, if any.
        private func predictWord(from path: [CGPoint], keyBounds: [String: CGRect]) -> String? {
            guard path.count > 5 else { return nil }

            // Step 1: Convert path to noisy string
            // Sample every 3rd point to reduce noise slightly
            var noisyString = ""
            var lastKey = ""

            for i in stride(from: 0, to: path.count, by: 3) {
                let point = path[i]
                // Find which key contains this point
                if let key = keyBounds.first(where: { $0.value.contains(point) })?.key {
                    if key != lastKey && key.count == 1 {  // Single char keys only
                        noisyString += key.lowercased()
                        lastKey = key
                    }
                }
            }

            guard noisyString.count >= 2 else { return nil }

            // Step 2: Let UITextChecker clean up the noise
            // "hgfdertyuiolklo" → UITextChecker → ["hello", "hells", ...]
            let range = NSRange(location: 0, length: noisyString.utf16.count)
            let language = keyboardContext.locale.identifier

            let guesses = textChecker.guesses(
                forWordRange: range,
                in: noisyString,
                language: language
            ) ?? []

            return guesses.first
        }
    }
}
#endif
