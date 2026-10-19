import Foundation

// Stage layouts: designs for the stage display. Undoable edits; the stage display changes as soon as they're made.
extension PresentationCoordinator {
    /// The layout the stage display uses, or nil for the standard look.
    public var stageLayout: StageLayout? {
        project.stage.layoutID.flatMap { project.stageLayout(withID: $0) }
    }

    /// Adds a layout, copying `basedOn` if given (else one like the standard look), and returns it.
    @discardableResult
    public func addStageLayout(named name: String, basedOn layoutID: UUID? = nil) -> StageLayout? {
        recordingUndo("New Stage Layout") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            var layout = StageLayout.standard(name: trimmed.isEmpty ? "Stage Layout" : trimmed)
            if let layoutID {
                guard let source = project.stageLayout(withID: layoutID) else {
                    _ = reject(.unknownStageLayout)
                    return nil
                }
                // New region IDs, so a selection in the editor never points into two layouts.
                let regions = source.regions.map {
                    StageRegion(kind: $0.kind, frame: $0.frame, fontSize: $0.fontSize, color: $0.color,
                                alignment: $0.alignment, showsLabel: $0.showsLabel)
                }
                layout = StageLayout(name: layout.name, regions: regions, background: source.background)
            }
            project.stageLayouts.append(layout)
            lastRejection = nil
            return layout
        }
    }

    /// Replaces the layout with the same ID. Region frames are kept on screen.
    @discardableResult
    public func updateStageLayout(_ layout: StageLayout) -> CommandResult {
        recordingUndo("Edit Stage Layout", coalescing: "stage-layout-\(layout.id)") {
            guard let index = project.stageLayouts.firstIndex(where: { $0.id == layout.id }) else {
                return reject(.unknownStageLayout)
            }
            var updated = layout
            for region in updated.regions.indices {
                updated.regions[region].frame = updated.regions[region].frame.clampedToCanvas()
                updated.regions[region].fontSize = min(max(updated.regions[region].fontSize, StageRegion.fontSizeRange.lowerBound),
                                                       StageRegion.fontSizeRange.upperBound)
            }
            project.stageLayouts[index] = updated
            return applied()
        }
    }

    /// Deletes a layout. If the stage display was using it, it goes back to the standard look.
    @discardableResult
    public func deleteStageLayout(_ layoutID: UUID) -> CommandResult {
        recordingUndo("Delete Stage Layout") {
            guard project.stageLayout(withID: layoutID) != nil else { return reject(.unknownStageLayout) }
            project.stageLayouts.removeAll { $0.id == layoutID }
            if project.stage.layoutID == layoutID { project.stage.layoutID = nil }
            return applied()
        }
    }

    /// Chooses the layout the stage display uses. Nil uses the standard look.
    @discardableResult
    public func setStageLayout(_ layoutID: UUID?) -> CommandResult {
        var settings = project.stage
        settings.layoutID = layoutID
        return setStageSettings(settings)
    }
}
