import AppKit
import os
import SwiftUI
import PresenterCore

/// What the audience sees, drawn as two layers like ProPresenter: the background layer, and the live slide's
/// content over it. Each transitions on its own, so a background that stays (a transparent slide) never moves.
/// Uses the same renderer as the operator's previews.
struct AudienceOutputView: View {
    let coordinator: PresentationCoordinator

    /// One layer's current value, the value it's replacing, and how far the slide transition between them has run.
    private struct Layer<Value: Equatable>: Equatable {
        var shown: Value
        var outgoing: Value?
        var progress = 1.0
        /// The transition playing (or last played). Kept once it's over, so the view's structure only changes with
        /// the content.
        var transition: PresenterCore.SlideTransition?
    }

    @State private var isBlack: Bool
    @State private var background: Layer<SlideBackground?>
    @State private var slide: Layer<SlideDocument?>
    /// The shown slide's element In transitions, and the outgoing slide's Out transitions, while they play.
    @State private var inClock: ElementClock?
    @State private var outClock: ElementClock?
    /// Counts slide changes, so a delayed clean-up only touches the change that scheduled it.
    @State private var generation = 0

    init(coordinator: PresentationCoordinator) {
        self.coordinator = coordinator
        let parts = Self.layers(of: coordinator.audienceScene)
        _isBlack = State(initialValue: parts.isBlack)
        _background = State(initialValue: Layer(shown: parts.background))
        _slide = State(initialValue: Layer(shown: parts.slide))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if !isBlack {
                    if let outgoing = background.outgoing {
                        backgroundView(outgoing).modifier(effect(background, role: .outgoing, opaque: true, canvas: proxy.size))
                    }
                    backgroundView(background.shown).modifier(effect(background, role: .incoming, opaque: true, canvas: proxy.size))
                    if let outgoing = slide.outgoing {
                        slideView(outgoing)
                            .environment(\.elementClock, outClock)
                            .modifier(effect(slide, role: .outgoing, opaque: false, canvas: proxy.size))
                    }
                    slideView(slide.shown)
                        .environment(\.elementClock, inClock)
                        .modifier(effect(slide, role: .incoming, opaque: false, canvas: proxy.size))
                    OverlayLayers(coordinator: coordinator)
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
        .onChange(of: coordinator.audienceScene) { _, scene in present(scene) }
    }

    private func effect<Value>(_ layer: Layer<Value>, role: TransitionMath.Role, opaque: Bool, canvas: CGSize) -> SlideTransitionEffect {
        SlideTransitionEffect(progress: layer.progress, transition: layer.transition, role: role, opaque: opaque, canvas: canvas)
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

    /// A different slide plays its transition, and its background transitions too only if it changed. Its elements
    /// play their own In transitions, and the previous slide's elements their Out transitions, without holding up
    /// the change. Cuts, clears, blackout and re-taking the same slide are instant; a change mid-transition starts
    /// from what's on screen now.
    private func present(_ scene: AudienceScene) {
        let next = Self.layers(of: scene)
        let wasBlack = isBlack
        isBlack = next.isBlack
        if next.isBlack {
            inClock = nil
            outClock = nil
            return
        }
        let current = slide.shown
        let isNewSlide = next.slide != nil && next.slide?.id != current?.id
        // Transitions play only from one slide to another, never out of black.
        let plays = !wasBlack && isNewSlide && current != nil
        let transition = plays ? next.slide?.transition : nil

        Self.update(to: next.background, transition: transition, get: { background }, set: { background = $0 })
        updateSlide(to: next.slide, transition: transition, playsOut: plays)
        if isNewSlide || next.slide == nil { startInClock(for: wasBlack ? nil : next.slide) }
    }

    /// The slide layer: like the background, but the outgoing slide also stays while its elements' Out transitions
    /// play, and its other elements go at once when there's no slide transition.
    private func updateSlide(to value: SlideDocument?, transition: PresenterCore.SlideTransition?, playsOut: Bool) {
        let current = slide
        guard value != current.shown else { return }
        let outEnd = playsOut ? (current.shown?.elementTransitionsEnd(.out) ?? 0) : 0
        let hold = max(transition?.duration ?? 0, outEnd)
        generation += 1
        guard hold > 0 else {
            slide = Layer(shown: value)
            outClock = nil
            return
        }
        outClock = outEnd > 0 ? ElementClock(phase: .out, start: .now, hidesStill: transition == nil) : nil
        slide = Layer(shown: value, outgoing: current.shown, progress: transition == nil ? 1 : 0, transition: transition)
        if let transition {
            withAnimation(.easeInOut(duration: transition.duration)) { slide.progress = 1 }
        }
        let scheduled = generation
        Task {
            try? await Task.sleep(for: .seconds(hold))
            guard generation == scheduled else { return }
            slide.outgoing = nil
            outClock = nil
        }
    }

    /// Plays the arriving slide's element In transitions, then stops the clock so nothing keeps redrawing.
    private func startInClock(for value: SlideDocument?) {
        guard let value, value.hasElementTransitions, value.elementTransitionsEnd(.in) > 0 else {
            inClock = nil
            return
        }
        let clock = ElementClock(phase: .in, start: .now)
        inClock = clock
        Task {
            try? await Task.sleep(for: .seconds(value.elementTransitionsEnd(.in)))
            if inClock == clock { inClock = nil }
        }
    }

    /// Reads and writes the layer only through `get`/`set`, so the animated write is never overwritten.
    private static func update<Value: Equatable>(
        to value: Value,
        transition: PresenterCore.SlideTransition?,
        get: @escaping () -> Layer<Value>,
        set: @escaping (Layer<Value>) -> Void
    ) {
        let current = get()
        guard value != current.shown else { return }
        guard let transition else {
            set(Layer(shown: value))
            return
        }
        let start = Layer(shown: value, outgoing: current.shown, progress: 0, transition: transition)
        set(start)
        var finished = start
        finished.progress = 1
        withAnimation(.easeInOut(duration: transition.duration)) {
            set(finished)
        } completion: {
            // Only drop the layer this transition added; a newer change may already have replaced it.
            guard get() == finished else { return }
            var settled = finished
            settled.outgoing = nil
            set(settled)
        }
    }
}
