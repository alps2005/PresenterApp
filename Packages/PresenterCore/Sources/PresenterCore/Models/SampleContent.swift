import Foundation

extension ProjectDocument {
    /// Original demo content for first launch. Contains no third-party lyrics or texts.
    public static func sample() -> ProjectDocument {
        let welcome = PresentationDocument(title: "Welcome", slides: [
            .text("Welcome", role: .title),
            .text("We're glad you're here.\nPlease silence your phones.", notes: "Wait for the room to settle."),
        ])
        let announcements = PresentationDocument(title: "Announcements", slides: [
            .text("Community Lunch\nSunday after the service"),
            .text("Volunteers Needed\nSign up at the welcome desk"),
            .text("Youth Night\nFriday at 7 PM"),
        ])
        let closing = PresentationDocument(title: "Closing", slides: [
            .text("Thank you for coming", role: .title),
            .text("See you next week!"),
        ])
        let presentations = [welcome, announcements, closing]
        return ProjectDocument(
            name: "Sample Service",
            presentations: presentations,
            playlist: PlaylistDocument(
                title: "Sunday Service",
                items: presentations.map { PresentationItem(presentationID: $0.id) }
            )
        )
    }
}
