import AppKit
import os
import SwiftUI
import PresenterCore

/// What the audience sees, drawn as two layers like ProPresenter: the background layer, and the live slide's
/// content over it. Each cross-fades on its own, so a background that stays (a transparent slide) never fades.
/// Uses the same renderer as the operator's previews.
struct AudienceOutputView: View {
    let coordinator: PresentationCoordinator

    /// One layer's current value, the value fading out under it, and the current value's opacity.
    private struct Layer<Value: Equatable>: Equatable {
        var shown: Value
        var outgoing: Value?
        var opacity = 1.0
    }

    @State private var isBlack: Bool
    @State private var background: Layer<SlideBackground?>
    @State private var slide: Layer<SlideDocument?>

    init(coordinator: PresentationCoordinator) {
        self.coordinator = coordinator
        let parts = Self.layers(of: coordinator.audienceScene)
        _isBlack = State(initialValue: parts.isBlack)
        _background = State(initialValue: Layer(shown: parts.background))
        _slide = State(initialValue: Layer(shown: parts.slide))
    }

    var body: some View {
        ZStack {
            Color.black
            if !isBlack {
                if let outgoing = background.outgoing { backgroundView(outgoing) }
                backgroundView(background.shown).opacity(background.opacity)
                if let outgoing = slide.outgoing { slideView(outgoing) }
                slideView(slide.shown).opacity(slide.opacity)
                OverlayLayers(coordinator: coordinator)
            }
        }
        .ignoresSafeArea()
        .onChange(of: coordinator.audienceScene) { _, scene in present(scene) }
    }

    private func backgroundView(_ value: SlideBackground?) -> some View {
        SlideRenderView(scene: value.map { .background($0) } ?? .empty)
    }

    @ViewBuilder
    private func slideView(_ value: SlideDocument?) -> some View {
        if let value {
            SlideRenderView(scene: .slide(RenderedSlide(slide: value, background: .transparent)), transparency: .clear)
        }
    }

    private static func layers(of scene: AudienceScene) -> (isBlack: Bool, background: SlideBackground?, slide: SlideDocument?) {
        switch scene {
        case .black: (true, nil, nil)
        case .empty: (false, nil, nil)
        case .background(let background): (false, background, nil)
        case .slide(let rendered): (false, rendered.background, rendered.slide)
        }
    }

    /// A different slide with a dissolve fades in, and its background fades too only if it changed. Cuts, clears,
    /// blackout and re-taking the same slide are instant; a change mid-fade starts from what's on screen now.
    private func present(_ scene: AudienceScene) {
        let next = Self.layers(of: scene)
        let wasBlack = isBlack
        isBlack = next.isBlack
        let dissolve: Double? = {
            guard !wasBlack, !next.isBlack, let incoming = next.slide, let transition = incoming.transition,
                  let current = slide.shown, current.id != incoming.id else { return nil }
            return transition.duration
        }()
        if next.isBlack { return }
        Self.update(to: next.background, dissolve: dissolve, get: { background }, set: { background = $0 })
        Self.update(to: next.slide, dissolve: dissolve, get: { slide }, set: { slide = $0 })
    }

    /// Reads and writes the layer only through `get`/`set`, so the animated write is never overwritten.
    private static func update<Value: Equatable>(
        to value: Value,
        dissolve: Double?,
        get: @escaping () -> Layer<Value>,
        set: @escaping (Layer<Value>) -> Void
    ) {
        let current = get()
        guard value != current.shown else { return }
        guard let dissolve else {
            set(Layer(shown: value))
            return
        }
        let start = Layer(shown: value, outgoing: current.shown, opacity: 0)
        set(start)
        var faded = start
        faded.opacity = 1
        withAnimation(.easeInOut(duration: dissolve)) {
            set(faded)
        } completion: {
            // Only drop the layer this fade added; a newer change may already have replaced it.
            guard get() == faded else { return }
            var settled = faded
            settled.outgoing = nil
            set(settled)
        }
    }
}
