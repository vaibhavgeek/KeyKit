//
//  SwipeContext.swift
//  KeyboardKit
//
//  Created by Daniel Saidi on 2025-11-29.
//  Copyright © 2025 Daniel Saidi. All rights reserved.
//

import SwiftUI

/// This context has observable swipe-related state and is
/// used for tracking swipe gestures on the keyboard.
///
/// KeyboardKit will create an instance of this context, and
/// inject into the environment.
public class SwipeContext: ObservableObject {

    /// Create a swipe context.
    public init() {}


    /// Whether a swipe gesture is currently active.
    @Published public var isSwiping: Bool = false

    /// The path points collected during the swipe gesture.
    @Published public var path: [CGPoint] = []

    /// Map of keys to their screen positions.
    public var keyBounds: [String: CGRect] = [:]

    /// Start a swipe gesture at the given point.
    public func start(at point: CGPoint) {
        isSwiping = true
        path = [point]
    }

    /// Update the swipe gesture with a new point.
    public func update(with point: CGPoint) {
        guard isSwiping else { return }
        path.append(point)
    }

    /// End the swipe gesture and fade out the path.
    public func end() {
        isSwiping = false
        // Fade out after 0.2s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.path.removeAll()
        }
    }
}
