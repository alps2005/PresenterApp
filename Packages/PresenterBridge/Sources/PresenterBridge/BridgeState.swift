import Foundation
import PresenterCore

/// What the app draws, read after each command. Slides come ready to draw: themed, with their background resolved
/// and media as file paths, on the same 1920×1080 canvas as the Mac app.
@MainActor
struct BridgeState: Encodable {
    struct Show: Encodable {
        var id: UUID
        var title: String
    }

    struct Item: Encodable {
        var id: UUID
        var presentationID: UUID
        var title: String
        var kind: String
        var slideCount: Int
    }

    struct LibraryEntry: Encodable {
        var id: UUID
        var title: String
        var kind: String
        var slideCount: Int
    }

    struct Position: Encodable {
        var itemID: UUID
        var slideID: UUID
        var occurrence: Int

        init(_ position: SlidePosition) {
            itemID = position.itemID
            slideID = position.slideID
            occurrence = position.occurrence
        }
    }

    /// One slide of the selected item, in the order it plays.
    struct SlideEntry: Encodable {
        var position: Position
        var label: String?
        /// The label's kind ("verse", "chorus"…), for its colour. Nil without a label.
        var section: String?
        var slide: BridgeSlide
    }

    var projectName: String
    var projectRevision: Int
    var problem: String?
    var shows: [Show]
    var activeShowID: UUID
    var items: [Item]
    var selectedItemID: UUID?
    var library: [LibraryEntry]
    var slides: [SlideEntry]
    var cued: Position?
    var live: Position?
    /// What the audience sees now. Nil while blacked out.
    var audience: BridgeSlide?
    var isBlackout: Bool
    var canRestore: Bool
    /// A song's credit line on its first and last slides, when the project shows credits.
    var credits: String?
    var undoName: String?
    var redoName: String?

    init(session: BridgeSession, now: Date) {
        let coordinator = session.coordinator
        let project = coordinator.project
        let state = coordinator.state
        let media = { (assetID: UUID) in session.mediaPath(assetID) }

        projectName = project.name
        projectRevision = session.projectRevision
        problem = session.problem
        shows = project.playlists.map { Show(id: $0.id, title: $0.title) }
        activeShowID = project.activePlaylistID
        items = project.playlist.items.map { item in
            let presentation = project.presentation(withID: item.presentationID)
            return Item(id: item.id, presentationID: item.presentationID, title: presentation?.title ?? "Missing presentation",
                        kind: presentation?.kind.rawValue ?? "presentation", slideCount: presentation?.arrangedSlides.count ?? 0)
        }
        selectedItemID = state.selectedItemID
        library = project.presentations
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
            .map { LibraryEntry(id: $0.id, title: $0.title, kind: $0.kind.rawValue, slideCount: $0.slides.count) }

        slides = []
        if let itemID = state.selectedItemID, let presentation = project.presentation(forItem: itemID) {
            slides = presentation.arrangedSlides.compactMap { arranged in
                guard let slide = presentation.slide(withID: arranged.slideID) else { return nil }
                let rendered = project.rendered(slide, in: presentation)
                return SlideEntry(
                    position: Position(SlidePosition(itemID: itemID, slideID: arranged.slideID, occurrence: arranged.occurrence)),
                    label: slide.label,
                    section: slide.label.map { SongSectionKind(label: $0).key },
                    slide: BridgeSlide(rendered, media: media)
                )
            }
        }
        cued = state.preview.map(Position.init)
        live = state.live.map { Position($0.position) }

        audience = switch coordinator.audienceScene {
        case .black: nil
        case .empty: BridgeSlide(background: nil, elements: [], media: media)
        case .background(let background): BridgeSlide(background: background, elements: [], media: media)
        case .slide(let rendered):
            BridgeSlide(rendered, media: media) { coordinator.liveText($0, at: now) }
        }
        isBlackout = state.isBlackout
        canRestore = coordinator.canRestore
        credits = coordinator.audienceCredits
        undoName = coordinator.canUndo ? coordinator.undoActionName : nil
        redoName = coordinator.canRedo ? coordinator.redoActionName : nil
    }
}

/// A slide ready to draw: its background and its elements, bottom to top.
struct BridgeSlide: Encodable {
    struct Background: Encodable {
        /// "default" (the app's dark gradient), "color", "image", "video" (drawn as its first frame, or black) or
        /// "transparent" (whatever is on screen shows through).
        var kind: String
        var color: RGBAColor?
        var path: String?
        var scaling: String?
        var dimming: Double?
    }

    struct Element: Encodable {
        /// "text", "shape" or "image".
        var kind: String
        /// Where it sits, in 0…1 of the canvas. Nil for text in the centred flow (stacked, 120 points in from the
        /// edges, 48 apart).
        var frame: NormalizedRect?
        var text: String?
        var verticalAlignment: String?
        var style: TextStyle?
        var shape: String?
        var fill: RGBAColor?
        var stroke: RGBAColor?
        var strokeWidth: Double?
        var cornerRadius: Double?
        var path: String?
        var scaling: String?
        var opacity: Double?
    }

    var background: Background
    var elements: [Element]

    init(_ rendered: RenderedSlide, media: (UUID) -> String?, text: (String) -> String = { $0 }) {
        self.init(background: rendered.background, elements: rendered.slide.elements, media: media, text: text)
    }

    init(background: SlideBackground?, elements: [SlideElement], media: (UUID) -> String?, text: (String) -> String = { $0 }) {
        self.background = switch background {
        case nil: Background(kind: "default")
        case .transparent: Background(kind: "transparent")
        case .color(let color): Background(kind: "color", color: color)
        case .image(let image):
            Background(kind: "image", path: media(image.assetID), scaling: image.scaling.rawValue, dimming: image.dimming)
        case .video(let video):
            Background(kind: "video", path: media(video.assetID), scaling: video.scaling.rawValue, dimming: video.dimming)
        }
        self.elements = elements.map { element in
            switch element {
            case .text(let element):
                Element(kind: "text", frame: element.box?.frame, text: text(element.text),
                        verticalAlignment: (element.box?.verticalAlignment ?? .center).rawValue, style: element.style)
            case .shape(let shape):
                Element(kind: "shape", frame: shape.frame, shape: shape.kind.rawValue, fill: shape.fill, stroke: shape.stroke,
                        strokeWidth: shape.strokeWidth, cornerRadius: shape.cornerRadius)
            case .image(let image):
                Element(kind: "image", frame: image.frame, path: media(image.assetID), scaling: image.scaling.rawValue,
                        opacity: image.opacity)
            }
        }
    }
}
