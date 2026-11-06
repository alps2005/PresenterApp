import Foundation

/// Something to fix before a service, found by `PreServiceCheck`.
public struct PreServiceProblem: Identifiable, Hashable, Sendable {
    public enum Kind: Int, Comparable, Sendable, CaseIterable {
        /// The audience output is off, on a display that's gone, or behind the operator window.
        case output
        case missingMedia
        case missingFont
        /// A presentation in the show with nothing on any slide, like a New Presentation never filled in.
        case emptyPresentation
        /// A song with no writers, copyright or CCLI number, so no credits can show and the CCLI report has no number.
        case songWithoutCredits

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .output: Localization.text("Audience output")
            case .missingMedia: Localization.text("Missing media")
            case .missingFont: Localization.text("Missing fonts")
            case .emptyPresentation: Localization.text("Empty presentations")
            case .songWithoutCredits: Localization.text("Songs without credits")
            }
        }
    }

    public var kind: Kind
    public var message: String
    /// The show item it's in, so the operator can go there. Nil for problems outside the show (the output, themes).
    public var itemID: UUID?

    public var id: String { "\(kind.rawValue)|\(itemID?.uuidString ?? "")|\(message)" }

    public init(kind: Kind, message: String, itemID: UUID? = nil) {
        self.kind = kind
        self.message = message
        self.itemID = itemID
    }
}

/// Looks over the open show before a service, like a checklist: media files that are gone, fonts that aren't
/// installed, the audience display, presentations left empty and songs without credits. Only what the open show
/// uses counts (its presentations and their themes, the props and the macros), so old library items don't nag.
public enum PreServiceCheck {
    /// `includesOutputOff` is false at launch, when outputs are usually turned on later; a display that's gone
    /// counts either way.
    public static func problems(
        in project: ProjectDocument,
        mediaExists: (MediaAsset) -> Bool,
        installedFonts: Set<String>,
        audience: OutputStatus,
        includesOutputOff: Bool = true
    ) -> [PreServiceProblem] {
        var problems: [PreServiceProblem] = []

        switch audience {
        case .off where includesOutputOff:
            problems.append(.init(kind: .output, message: Localization.text("The audience output is off. Turn it on in the Output menu.")))
        case .displayMissing(let name):
            problems.append(.init(kind: .output, message: Localization.text("{0} isn't connected. The audience output shows on it when it's plugged in again.", name)))
        case .displayHasOperatorWindow(let name):
            problems.append(.init(kind: .output, message: Localization.text("The operator window is on {0}, so the audience output is hidden. Move the operator window to another screen.", name)))
        default:
            break
        }

        let items = project.playlist.items.compactMap { item in
            project.presentation(withID: item.presentationID).map { (item, $0) }
        }

        // Media: each missing file once, at the first show item that uses it.
        let missing = project.mediaAssets.filter { !mediaExists($0) }
        for asset in missing {
            let name = asset.originalFilename
            if let (item, presentation) = items.first(where: { uses(asset.id, $0.1, project: project) }) {
                problems.append(.init(kind: .missingMedia,
                                      message: Localization.text("“{0}” is missing, used in “{1}”.", name, title(presentation)), itemID: item.id))
            } else if project.props.uses(asset.id) {
                problems.append(.init(kind: .missingMedia, message: Localization.text("“{0}” is missing, used by a prop.", name)))
            } else if let macro = project.macrosUsing(asset: asset.id).first {
                problems.append(.init(kind: .missingMedia, message: Localization.text("“{0}” is missing, played by the macro “{1}”.", name, macro.name)))
            }
        }

        // Fonts, as the slides will draw them: under their theme, or as formatted by hand.
        var reportedFonts: Set<String> = []
        for (item, presentation) in items {
            let theme = project.theme(for: presentation)
            for slide in presentation.slides {
                for case .text(let text) in presentation.rendered(slide, theme: theme).slide.elements {
                    guard let family = text.style.fontFamily, !installedFonts.contains(family),
                          reportedFonts.insert(family).inserted else { continue }
                    problems.append(.init(kind: .missingFont,
                                          message: Localization.text("The font “{0}” isn't installed on this Mac, used in “{1}”. The system font shows instead.", family, title(presentation)),
                                          itemID: item.id))
                }
            }
        }

        for (item, presentation) in items {
            if presentation.background == nil, presentation.slides.allSatisfy(isEmpty) {
                problems.append(.init(kind: .emptyPresentation,
                                      message: Localization.text("“{0}” has nothing on its slides.", title(presentation)), itemID: item.id))
            }
            if presentation.kind == .song, presentation.song?.isEmpty ?? true {
                problems.append(.init(kind: .songWithoutCredits,
                                      message: Localization.text("“{0}” has no writers, copyright or CCLI number. Add them in the editor's Document › Song.", title(presentation)),
                                      itemID: item.id))
            }
        }
        return problems.sorted { $0.kind < $1.kind }
    }

    private static func title(_ presentation: PresentationDocument) -> String {
        presentation.title.isEmpty ? Localization.text("Untitled") : presentation.title
    }

    /// Whether the presentation, its theme's background or a slide action plays or shows the asset.
    private static func uses(_ assetID: UUID, _ presentation: PresentationDocument, project: ProjectDocument) -> Bool {
        presentation.uses(assetID)
            || project.theme(for: presentation)?.background?.assetID == assetID
            || presentation.slides.contains { $0.actions.contains { $0.audioAssetID == assetID } }
    }

    /// No words, picture, shape or background of its own.
    private static func isEmpty(_ slide: SlideDocument) -> Bool {
        slide.background == nil && slide.audioCue == nil && slide.elements.allSatisfy { element in
            if case .text(let text) = element { text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { false }
        }
    }
}
