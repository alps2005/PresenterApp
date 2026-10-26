import Foundation

// Songs from files, and the credits every song carries.
extension PresentationCoordinator {
    /// Adds imported songs to the library and the open show, in order, as one change to undo. Each gets its credits
    /// and, if the file gave a singing order, a "Song Order" arrangement that plays. Returns the new show items.
    @discardableResult
    public func importSongs(_ songs: [ImportedSong], maxLinesPerSlide: Int? = nil, themeID: UUID? = nil) -> [PresentationItem] {
        let songs = songs.filter { $0.slideCount > 0 }
        guard !songs.isEmpty else { return [] }
        return recordingUndo(songs.count == 1 ? "Import Song" : "Import Songs") {
            let theme = existingThemeID(themeID)
            // A SongSelect file names the church's licence; it fills in the project's if nobody has yet.
            if project.ccli.licenseNumber.isEmpty, let license = songs.first(where: { !$0.licenseNumber.isEmpty })?.licenseNumber {
                project.ccli.licenseNumber = license
            }
            var items: [PresentationItem] = []
            for song in songs {
                let arrangement = song.arrangement
                let presentation = PresentationDocument(
                    title: song.title.isEmpty ? "Untitled Song" : song.title,
                    slides: song.slides(maxLinesPerSlide: maxLinesPerSlide),
                    arrangements: arrangement.map { [$0] } ?? [],
                    activeArrangementID: arrangement?.id,
                    themeID: theme,
                    song: song.info.isEmpty ? nil : song.info,
                    kind: .song
                )
                let item = PresentationItem(presentationID: presentation.id)
                project.presentations.append(presentation)
                project.playlist.items.append(item)
                items.append(item)
            }
            state.selectedItemID = items.first?.id
            lastRejection = nil
            Log.coordinator.info("Imported \(items.count) songs")
            return items
        }
    }

    /// Sets the church's CCLI licence number (digits only) and whether songs show their credits.
    @discardableResult
    public func setCCLISettings(_ settings: CCLISettings) -> CommandResult {
        recordingUndo("CCLI Settings", coalescing: "ccli-settings") {
            let tidied = CCLISettings(licenseNumber: SongInfo.ccliNumber(from: settings.licenseNumber),
                                      showsCredits: settings.showsCredits)
            if project.ccli != tidied { project.ccli = tidied }
            return applied()
        }
    }

    /// The credit line the audience sees now: while a song with credits has its first or last slide live, and the
    /// project shows credits. Nil the rest of the time.
    public var audienceCredits: String? {
        guard project.ccli.showsCredits, !state.isBlackout, let live = state.live,
              let presentation = project.presentation(forItem: live.position.itemID),
              presentation.kind == .song, let song = presentation.song, !song.isEmpty else { return nil }
        let arranged = presentation.arrangedSlides
        let isFirstOrLast = [arranged.first, arranged.last].contains {
            $0?.slideID == live.position.slideID && $0?.occurrence == live.position.occurrence
        }
        guard isFirstOrLast else { return nil }
        return song.creditLine(title: presentation.title, licenseNumber: project.ccli.licenseNumber)
    }

    /// Sets a presentation's song credits. Empty credits are removed, so it no longer counts as a song with details.
    @discardableResult
    public func setSongInfo(_ info: SongInfo, presentationID: UUID) -> CommandResult {
        recordingUndo("Song Details", coalescing: "song-info-\(presentationID)") {
            guard presentationID != project.props.id else { return reject(.unknownPresentation) }
            let tidied = SongInfo(
                authors: info.authors.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                copyright: info.copyright.trimmingCharacters(in: .whitespaces),
                ccliNumber: SongInfo.ccliNumber(from: info.ccliNumber)
            )
            return editPresentation(presentationID) { $0.song = tidied.isEmpty ? nil : tidied }
        }
    }
}
