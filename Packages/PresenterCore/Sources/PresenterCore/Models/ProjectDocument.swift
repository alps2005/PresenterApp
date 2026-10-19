import Foundation

/// Top-level container for a show: the presentation library and the playlist that runs it.
public struct ProjectDocument: Identifiable, Codable, Hashable, Sendable {
    /// The file format version written to disk. Bump it whenever a release adds or changes a saved field:
    /// an older build then refuses the newer file (and moves it aside) instead of loading it, silently dropping
    /// the fields it doesn't know, and saving over it. Older versions load through the Codable defaults.
    ///
    /// - 1: presentations, playlist, slides, formatting, backgrounds and media (v0.1.0-beta.1).
    /// - 2: transparent backgrounds, song arrangements, timers, stage display, messages, props and video
    ///   (added in v0.1.0-beta.2, which still wrote 1; written as 2 from beta.3).
    /// - 3: themes, text that follows them, text outlines and text background boxes (v0.1.0-beta.5).
    /// - 4: automatic advancing (slide Go To Next timers, presentation Slideshow intervals); Fade Through Black, Push,
    ///   Wipe and Zoom slide transitions; and element transitions (v0.1.0-beta.9).
    /// - 5: library folders (v0.1.0-beta.11).
    public static let currentSchemaVersion = 5

    public let id: UUID
    public var name: String
    public var schemaVersion: Int
    public var presentations: [PresentationDocument]
    /// Folders that group the library's presentations (see `PresentationDocument.folderID`).
    public var libraryFolders: [LibraryFolder]
    public var playlist: PlaylistDocument
    /// Media files the project's slides reference. The files live in the media library folder.
    public var mediaAssets: [MediaAsset]
    /// Timers for the stage display and messages.
    public var timers: [TimerDefinition]
    public var stage: StageSettings
    public var messages: [MessageDefinition]
    /// Props are the slides of this presentation (see `PresentationDocument.propsLibrary`).
    public var props: PresentationDocument
    /// Looks that presentations can follow (see `Theme`).
    public var themes: [Theme]
    /// The theme new presentations and songs start with. Nil starts them without one.
    public var defaultThemeID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        schemaVersion: Int = ProjectDocument.currentSchemaVersion,
        presentations: [PresentationDocument] = [],
        libraryFolders: [LibraryFolder] = [],
        playlist: PlaylistDocument = PlaylistDocument(title: "Service"),
        mediaAssets: [MediaAsset] = [],
        timers: [TimerDefinition] = TimerDefinition.defaults(),
        stage: StageSettings = StageSettings(),
        messages: [MessageDefinition] = MessageDefinition.defaults(),
        props: PresentationDocument = .propsLibrary(),
        themes: [Theme] = Theme.presets(),
        defaultThemeID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.presentations = presentations
        self.libraryFolders = libraryFolders
        self.playlist = playlist
        self.mediaAssets = mediaAssets
        self.timers = timers
        self.stage = stage
        self.messages = messages
        self.props = props
        self.themes = themes
        self.defaultThemeID = defaultThemeID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, schemaVersion, presentations, libraryFolders, playlist, mediaAssets, timers, stage, messages, props, themes, defaultThemeID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        presentations = try container.decode([PresentationDocument].self, forKey: .presentations)
        libraryFolders = try container.decodeIfPresent([LibraryFolder].self, forKey: .libraryFolders) ?? []
        playlist = try container.decode(PlaylistDocument.self, forKey: .playlist)
        mediaAssets = try container.decodeIfPresent([MediaAsset].self, forKey: .mediaAssets) ?? []
        // Projects saved before timers existed get the default ones.
        timers = try container.decodeIfPresent([TimerDefinition].self, forKey: .timers) ?? TimerDefinition.defaults()
        stage = try container.decodeIfPresent(StageSettings.self, forKey: .stage) ?? StageSettings()
        messages = try container.decodeIfPresent([MessageDefinition].self, forKey: .messages) ?? MessageDefinition.defaults()
        props = try container.decodeIfPresent(PresentationDocument.self, forKey: .props) ?? .propsLibrary()
        // Projects saved before themes existed get the starting ones; their presentations follow none.
        themes = try container.decodeIfPresent([Theme].self, forKey: .themes) ?? Theme.presets()
        defaultThemeID = try container.decodeIfPresent(UUID.self, forKey: .defaultThemeID)
    }

    public func asset(withID assetID: UUID) -> MediaAsset? {
        mediaAssets.first { $0.id == assetID }
    }

    /// Library presentations with a background or image that uses the asset.
    public func presentationsUsing(asset assetID: UUID) -> [PresentationDocument] {
        presentations.filter { $0.uses(assetID) }
    }

    /// Themes whose background uses the asset.
    public func themesUsing(asset assetID: UUID) -> [Theme] {
        themes.filter { $0.background?.assetID == assetID }
    }

    /// A library presentation, or the props library (so the slide editor can edit props).
    public func presentation(withID presentationID: UUID) -> PresentationDocument? {
        if presentationID == props.id { return props }
        return presentations.first { $0.id == presentationID }
    }

    public func folder(withID folderID: UUID) -> LibraryFolder? {
        libraryFolders.first { $0.id == folderID }
    }

    public func prop(withID propID: UUID) -> SlideDocument? {
        props.slide(withID: propID)
    }

    public func theme(withID themeID: UUID) -> Theme? {
        themes.first { $0.id == themeID }
    }

    /// The theme a presentation follows, or nil if it follows none (or its theme was deleted).
    public func theme(for presentation: PresentationDocument) -> Theme? {
        presentation.themeID.flatMap { theme(withID: $0) }
    }

    /// A slide of `presentation`, ready to draw: themed, with its background resolved. Everything that draws a
    /// slide goes through here, so the editor, thumbnails, previews and the audience output agree.
    public func rendered(_ slide: SlideDocument, in presentation: PresentationDocument) -> RenderedSlide {
        presentation.rendered(slide, theme: theme(for: presentation))
    }

    public func message(withID messageID: UUID) -> MessageDefinition? {
        messages.first { $0.id == messageID }
    }

    /// The presentation a playlist item points at, or nil if the item or presentation is missing.
    public func presentation(forItem itemID: UUID) -> PresentationDocument? {
        guard let item = playlist.item(withID: itemID) else { return nil }
        return presentation(withID: item.presentationID)
    }

    public func slide(at position: SlidePosition) -> SlideDocument? {
        presentation(forItem: position.itemID)?.slide(withID: position.slideID)
    }

    /// The slide at a playlist position, ready to draw (see `rendered(_:in:)`).
    public func renderedSlide(at position: SlidePosition) -> RenderedSlide? {
        guard let presentation = presentation(forItem: position.itemID),
              let slide = presentation.slide(withID: position.slideID) else { return nil }
        return rendered(slide, in: presentation)
    }
}

/// Identifies one slide within one playlist entry. Uses stable IDs, never indices.
public struct SlidePosition: Codable, Hashable, Sendable {
    public var itemID: UUID
    public var slideID: UUID
    /// Which time the slide plays in its presentation's arrangement (0 = first). Repeats of a chorus are
    /// distinct positions, so Next and Previous step through them.
    public var occurrence: Int

    public init(itemID: UUID, slideID: UUID, occurrence: Int = 0) {
        self.itemID = itemID
        self.slideID = slideID
        self.occurrence = occurrence
    }

    private enum CodingKeys: String, CodingKey {
        case itemID, slideID, occurrence
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decode(UUID.self, forKey: .itemID)
        slideID = try container.decode(UUID.self, forKey: .slideID)
        occurrence = try container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 0
    }
}
