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
