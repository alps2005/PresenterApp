import Foundation

// Section keys: jumping straight to a song's verse, chorus or bridge while operating, as in ProPresenter.
extension PresentationCoordinator {
    /// Takes live the first slide of a section of the live presentation (or, with nothing live, the selected one), in
    /// its play order. With a `number`, the section whose label ends with it ("Verse 2"; a label without a number
    /// counts as 1). Without one, the next section of that kind after the live slide, wrapping round, so pressing the
    /// same key again moves on to the next verse.
    @discardableResult
    public func takeLiveSection(_ kind: SongSectionKind, number: Int? = nil) -> CommandResult {
        guard let itemID = state.live?.position.itemID ?? state.selectedItemID else { return reject(.nothingLive) }
        guard let presentation = project.presentation(forItem: itemID) else { return reject(.unknownItem) }
        let starts = sectionStarts(in: presentation, kind: kind, number: number)
        guard !starts.isEmpty else { return reject(.noSuchSection) }

        var target = starts[0].slide
        if number == nil, let live = state.live?.position, live.itemID == itemID {
            let arranged = presentation.arrangedSlides
            let liveIndex = arranged.firstIndex { $0.slideID == live.slideID && $0.occurrence == live.occurrence }
            if let liveIndex, let next = starts.first(where: { $0.index > liveIndex }) { target = next.slide }
        }
        return takeLive(slideID: target.slideID, inItem: itemID, occurrence: target.occurrence)
    }

    /// How many sections of a kind the selected or live presentation plays, so a key can tell whether a number may
    /// follow it.
    public func sectionCount(_ kind: SongSectionKind) -> Int {
        guard let itemID = state.live?.position.itemID ?? state.selectedItemID,
              let presentation = project.presentation(forItem: itemID) else { return 0 }
        return Set(sectionStarts(in: presentation, kind: kind, number: nil).compactMap {
            presentation.slide(withID: $0.slide.slideID)?.label
        }).count
    }

    /// Where each matching section starts in the play order: the first slide of every run of slides with a matching
    /// label, so a section played twice starts twice.
    private func sectionStarts(in presentation: PresentationDocument, kind: SongSectionKind,
                               number: Int?) -> [(index: Int, slide: ArrangedSlide)] {
        var starts: [(index: Int, slide: ArrangedSlide)] = []
        var previousLabel: String?
        for (index, arranged) in presentation.arrangedSlides.enumerated() {
            let label = presentation.slide(withID: arranged.slideID)?.label
            defer { previousLabel = label }
            guard let label, label != previousLabel, SongSectionKind(label: label) == kind else { continue }
            if let number, (SongSectionKind.number(inLabel: label) ?? 1) != number { continue }
            starts.append((index, arranged))
        }
        return starts
    }
}
