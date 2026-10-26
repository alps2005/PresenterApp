import Foundation

/// What a library presentation holds, so the operator can tell songs, Bible passages and slide decks apart at a glance.
/// Set when the item is made (New Song, song import, Scripture), and changeable afterwards.
public enum PresentationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case presentation
    case song
    case scripture

    /// The kind of a presentation saved before kinds existed, from what its slides look like: credits, group labels
    /// or an arrangement make a song (only songs get labels); a caption on every slide, as Scripture adds, makes a
    /// passage; anything else is a presentation.
    public static func guessed(for presentation: PresentationDocument) -> PresentationKind {
        if presentation.song != nil || !presentation.arrangements.isEmpty
            || presentation.slides.contains(where: { $0.label != nil }) {
            return .song
        }
        let everySlideHasACaption = !presentation.slides.isEmpty && presentation.slides.allSatisfy { slide in
            slide.elements.contains { element in
                if case .text(let text) = element { text.role == .caption } else { false }
            }
        }
        return everySlideHasACaption ? .scripture : .presentation
    }
}
