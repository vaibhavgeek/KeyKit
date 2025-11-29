//
//  Gestures+SwipePathView.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2025-11-29.
//  Copyright © 2025 Daniel Saidi. All rights reserved.
//

import SwiftUI

public extension Gestures {

    /// This view renders the swipe path as the user drags
    /// their finger across the keyboard.
    ///
    /// The path is drawn as a line that automatically fades
    /// out when the swipe gesture ends.
    struct SwipePathView: View {

        /// Create a swipe path view.
        ///
        /// - Parameters:
        ///   - swipeContext: The swipe context to use.
        public init(swipeContext: SwipeContext) {
            self.swipeContext = swipeContext
        }

        @ObservedObject
        private var swipeContext: SwipeContext

        public var body: some View {
            if swipeContext.isSwiping && swipeContext.path.count > 1 {
                Path { path in
                    path.addLines(swipeContext.path)
                }
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 5)
                .allowsHitTesting(false)  // Critical: lets taps pass through
            }
        }
    }
}
