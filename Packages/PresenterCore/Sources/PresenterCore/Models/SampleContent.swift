import Foundation

extension ProjectDocument {
    /// What a new install starts with: the starting themes and nothing else. No presentations, media, timers,
    /// messages or props, so the operator's library holds only what they add.
    public static func starter() -> ProjectDocument {
        ProjectDocument(name: "My Show", timers: [], messages: [], props: .propsLibrary(slides: []))
    }

    /// Demo content for tests, previews and layout checks; never opened for operators. Contains no third-party
    /// lyrics or texts.
    public static func sample() -> ProjectDocument {
        // Shows formatting without any imported media: a coloured background and a styled, repositioned title.
        var welcomeTitle = TextElement(text: "Welcome", role: .title)
        welcomeTitle.style.fontFamily = "Georgia"
        welcomeTitle.style.fontSize = 160
        welcomeTitle.style.alignment = .leading
        welcomeTitle.box = .preset(.bottomLeading)
        let welcome = PresentationDocument(
            title: "Welcome",
            slides: [
                SlideDocument(elements: [.text(welcomeTitle)]),
                .text("We're glad you're here.\nPlease silence your phones.", notes: "Wait for the room to settle."),
            ],
            background: .color(RGBAColor(red: 0.11, green: 0.23, blue: 0.36))
        )
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
