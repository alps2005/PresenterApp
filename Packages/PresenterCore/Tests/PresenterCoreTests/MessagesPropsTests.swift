import Foundation
import XCTest
@testable import PresenterCore

@MainActor
final class MessagesPropsTests: XCTestCase {
    func testMessageFieldsAndRendering() {
        let message = MessageDefinition(name: "Nursery", text: "Child {Number} · {Room} · {Number} · {timer: Sermon} left")
        XCTAssertEqual(message.fields, ["Number", "Room"])
        let text = message.rendered(values: ["Number": "12"]) { $0 == "Sermon" ? "4:05" : nil }
        XCTAssertEqual(text, "Child 12 ·  · 12 · 4:05 left")
    }

    func testMessageTimerTokensUseLiveTimers() {
        var clock = Date(timeIntervalSince1970: 0)
        let timer = TimerDefinition(name: "Sermon", kind: .countdown(seconds: 300))
        let message = MessageDefinition(name: "M", text: "{timer:sermon} left")
        let c = PresentationCoordinator(project: ProjectDocument(name: "T", timers: [timer], messages: [message]))
        c.now = { clock }
        c.startTimer(timer.id)
        clock += 55
        XCTAssertEqual(c.messageText(message, values: [:], at: clock), "4:05 left")
    }

    func testShowClearAndRestoreMessagesAndProps() {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let message = c.project.messages[0]
        let logo = c.project.props.slides[0]

        XCTAssertEqual(c.showMessage(message.id, values: ["Number": "7"]), .applied)
        XCTAssertEqual(c.toggleProp(logo.id), .applied)
        XCTAssertEqual(c.audienceMessage?.values, ["Number": "7"])
        XCTAssertEqual(c.audienceProps.map(\.id), [logo.id])

        c.blackout()
        XCTAssertNil(c.audienceMessage)
        XCTAssertTrue(c.audienceProps.isEmpty)
        c.restoreOutput()

        XCTAssertEqual(c.clearAll(), .applied)
        XCTAssertNil(c.state.activeMessage)
        XCTAssertTrue(c.state.activeProps.isEmpty)
        XCTAssertTrue(c.canRestore)
        c.restoreOutput()
        XCTAssertEqual(c.state.activeMessage?.messageID, message.id)
        XCTAssertEqual(c.state.activeProps, [logo.id])

        c.toggleProp(logo.id)
        XCTAssertTrue(c.state.activeProps.isEmpty)
        XCTAssertEqual(c.clearProps(), .rejected(.nothingToClear))
        XCTAssertEqual(c.showMessage(UUID()), .rejected(.unknownMessage))
    }

    func testPropsAreEditedThroughTheSlideEditorCommands() {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        let prop = c.addProp(name: "Bug")
        let shape = SlideElement.shape(ShapeElement(kind: .ellipse, frame: .centered(width: 0.1, height: 0.1)))

        XCTAssertEqual(c.addElement(shape, toSlide: prop.id, inPresentation: c.project.props.id), .applied)
        XCTAssertEqual(c.project.prop(withID: prop.id)?.elements.count, 2)
        XCTAssertEqual(c.project.prop(withID: prop.id)?.label, "Bug")

        c.toggleProp(prop.id)
        c.deleteProp(prop.id)
        XCTAssertTrue(c.state.activeProps.isEmpty)
        c.undo()
        XCTAssertNotNil(c.project.prop(withID: prop.id))
    }

    func testPropsLibraryIsNotAPlaylistPresentation() {
        let c = PresentationCoordinator(project: ProjectDocument(name: "T"))
        XCTAssertNil(c.addToPlaylist(c.project.props.id))
        XCTAssertEqual(c.deletePresentation(c.project.props.id), .rejected(.unknownPresentation))
        XCTAssertFalse(c.project.presentations.contains { $0.id == c.project.props.id })
    }

    func testOldProjectsGetDefaultMessagesAndProps() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProjectDocument(name: "P"))) as! [String: Any]
        json.removeValue(forKey: "messages"); json.removeValue(forKey: "props")
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.messages.map(\.name), ["Nursery"])
        XCTAssertEqual(decoded.props.slides.map(\.label), ["Logo"])
    }
}
