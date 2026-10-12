import SwiftUI
import AppKit
import CoreText
@preconcurrency import CoreGraphics

// MARK: - First-launch flag

enum BevelWelcome {

    static let seenKey = "hasSeenWelcome"

    static var hasSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }
}

// MARK: - Metrics & Timing

enum WelcomeMetrics {

    static let size = CGSize(width: 780, height: 540)
    static let corner: CGFloat = 36

    // How long each greeting rests in the lens before the wheel turns (seconds).
    static let step: Double = 1.15

    // The little click-and-drag dot starts this long before the wheel turns (seconds).
    static let gestureLead: Double = 0.30
}

// MARK: - Greetings

struct WelcomeGreeting {

    let text: String
    let fontNames: [String]
    let size: CGFloat

    init(_ text: String, fonts: [String], size: CGFloat = 70) {
        self.text = text
        self.fontNames = fonts
        self.size = size
    }

    func makeFont() -> NSFont {
        for name in fontNames {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size, weight: .light)
    }

    var swiftUIFont: Font {
        Font(makeFont() as CTFont)
    }

    /// How far (in points, downward) the text must move so the middle of its actual
    /// glyphs, not of its line box, sits on the centre. Every typeface has different
    /// ascent, descent and glyph heights, so this is measured per greeting.
    var verticalCorrection: CGFloat {
        let font = makeFont()
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let lineCentre = (font.ascender + font.descender) / 2
        return glyphs.midY - lineCentre
    }

    static let corrections: [CGFloat] = all.map { $0.verticalCorrection }

    private static let script = ["SnellRoundhand-Black", "SnellRoundhand-Bold", "SnellRoundhand"]

    static let all: [WelcomeGreeting] = [
        WelcomeGreeting("hello", fonts: script, size: 80),
        WelcomeGreeting("你好", fonts: ["STKaiti", "STKaitiSC-Regular", "Kaiti SC"], size: 68),
        WelcomeGreeting("bonjour", fonts: script, size: 80),
        WelcomeGreeting("こんにちは", fonts: ["HiraMinProN-W6", "HiraMinProN-W3"], size: 62),
        WelcomeGreeting("hola", fonts: script, size: 80),
        WelcomeGreeting("مرحبا", fonts: ["DiwanThuluth", "GeezaPro-Bold"], size: 72),
        WelcomeGreeting("안녕하세요", fonts: ["AppleMyungjo", "AppleSDGothicNeo-Regular"], size: 60),
        WelcomeGreeting("नमस्ते", fonts: ["DevanagariSangamMN-Bold", "DevanagariSangamMN"], size: 68)
    ]
}

// MARK: - Liquid glass helper

extension View {

    /// Real Liquid Glass on macOS 26, a frosted-material look on older systems.
    @ViewBuilder
    func welcomeGlass<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 6)
        }
    }
}

// MARK: - Greeting wheel

/// The greetings are stacked in a vertical wheel that turns through a glass lens.
/// The word in the lens is crisp and bright; the ones above and below are smaller,
/// dimmer and softly blurred, so you can see what is coming and what has passed.
struct WelcomeGreetingWheel: View {

    let index: Int
    let visible: Bool
    let gestureStart: Date?

    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let spacing: CGFloat = 98

    var body: some View {
        ZStack {
            lens
            ForEach(0..<WelcomeGreeting.all.count, id: \.self) { i in
                row(i)
            }
            gesture
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.96)
    }

    private var lens: some View {
        Color.clear
            .frame(width: 500, height: 112)
            .welcomeGlass(RoundedRectangle(cornerRadius: 56, style: .continuous))
    }

    private func row(_ i: Int) -> some View {

        let d = i - index
        let distance = abs(d)

        let scale: CGFloat = distance == 0 ? 1 : (distance == 1 ? 0.55 : 0.4)
        let opacity: Double = distance == 0 ? 1 : (distance == 1 ? 0.5 : (distance == 2 ? 0.16 : 0))
        let blur: CGFloat = distance == 0 ? 0 : (distance == 1 ? 1.5 : 5)

        return Text(WelcomeGreeting.all[i].text)
            .font(WelcomeGreeting.all[i].swiftUIFont)
            .foregroundStyle(Color.white)
            .shadow(color: Color(red: 0.08, green: 0.22, blue: 0.70).opacity(0.35), radius: 8, x: 0, y: 3)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: 460)
            .offset(y: WelcomeGreeting.corrections[i])
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: CGFloat(d) * spacing)
    }

    // MARK: Click-and-drag dot

    /// A single small dot beside the lens. Just before each turn it presses in,
    /// drags upward as the wheel turns, then lets go and fades.
    private var gesture: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            gestureDot(at: context.date)
        }
        .offset(x: 296)
    }

    private func unit(_ x: Double) -> Double {
        min(max(x, 0), 1)
    }

    private func gestureDot(at date: Date) -> some View {

        let lead = WelcomeMetrics.gestureLead
        let e: Double = (gestureStart.map { date.timeIntervalSince($0) } ?? -1)
        let live = !reduceMotion && e >= 0

        let press = unit(e / 0.12)
        let release = unit((e - lead - 0.6) / 0.2)
        let drag = 1 - pow(1 - unit((e - lead) / 0.6), 3)

        let fadeIn = unit(e / 0.10)
        let fadeOut = 1 - unit((e - lead - 0.62) / 0.25)
        let alpha = live ? 0.9 * fadeIn * fadeOut : 0

        let scale = CGFloat(1 - 0.35 * press * (1 - release))
        let y = CGFloat(18 - 36 * drag)

        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .scaleEffect(scale)
            .opacity(alpha)
            .offset(y: y)
    }
}

// MARK: - Backdrop

struct WelcomeBackdrop: View {

    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in

            let t: Double = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate

            ZStack {

                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.33, blue: 0.82),
                        Color(red: 0.25, green: 0.55, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                blob(Color(red: 0.55, green: 0.80, blue: 1.00),
                     x: CGFloat(sin(t * 0.35) * 150),
                     y: CGFloat(cos(t * 0.27) * 60) - 40,
                     size: 400)

                blob(Color(red: 0.38, green: 0.32, blue: 0.96),
                     x: CGFloat(cos(t * 0.30) * 180),
                     y: CGFloat(sin(t * 0.40) * 90) + 110,
                     size: 360)

                blob(Color(red: 0.20, green: 0.86, blue: 0.96),
                     x: CGFloat(sin(t * 0.22 + 1.0) * 160),
                     y: CGFloat(cos(t * 0.33) * 50) - 130,
                     size: 320)

                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.20)],
                    center: .center,
                    startRadius: 220,
                    endRadius: 560
                )
            }
        }
    }

    private func blob(_ color: Color, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.55))
            .frame(width: size, height: size)
            .blur(radius: 70)
            .offset(x: x, y: y)
    }
}

// MARK: - Button style

struct WelcomeButtonStyle: ButtonStyle {

    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {

        let label = configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(prominent ? Color(red: 0.08, green: 0.26, blue: 0.68) : Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)

        if prominent {
            label
                .background(Capsule().fill(Color.white.opacity(0.95)))
                .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        } else {
            label
                .welcomeGlass(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Key cap

struct WelcomeKeyCap: View {

    let label: String
    var side: CGFloat = 52

    var body: some View {
        Text(label)
            .font(.system(size: side * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(minWidth: side, minHeight: side)
            .padding(.horizontal, 4)
            .welcomeGlass(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
    }
}

// MARK: - Model

final class WelcomeModel: ObservableObject {

    enum Stage {
        case greetings
        case tour
    }

    static let pageCount = 6

    @Published var stage: Stage = .greetings
    @Published var greetingIndex = 0
    @Published var wheelVisible = false
    @Published var gestureStart: Date? = nil
    @Published var pageIndex = 0

    var onClose: (() -> Void)?

    private var generation = 0

    var isLastPage: Bool {
        pageIndex >= WelcomeModel.pageCount - 1
    }

    // MARK: Greeting sequence

    func start() {

        generation += 1
        stage = .greetings

        var reset = Transaction()
        reset.disablesAnimations = true

        withTransaction(reset) {
            self.greetingIndex = 0
            self.wheelVisible = false
            self.gestureStart = nil
        }

        later(0.25) {
            withAnimation(.easeOut(duration: 0.8)) {
                self.wheelVisible = true
            }
            self.advance(from: 0)
        }
    }

    /// Runs `work` after a delay, unless the sequence was cancelled or restarted.
    private func later(_ delay: Double, _ work: @escaping () -> Void) {

        let token = generation

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == token else { return }
            work()
        }
    }

    /// Rests on the current greeting, then plays the click-and-drag cue and turns the
    /// wheel to the next one.
    private func advance(from index: Int) {

        let lead = WelcomeMetrics.gestureLead
        let extra: Double = index == 0 ? 0.45 : 0

        later(WelcomeMetrics.step + extra - lead) {

            let next = index + 1

            guard next < WelcomeGreeting.all.count else {
                self.later(lead) { self.enterTour() }
                return
            }

            self.gestureStart = Date()

            self.later(lead) {

                let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                let animation: Animation = reduce
                    ? .easeInOut(duration: 0.25)
                    : .spring(response: 0.75, dampingFraction: 0.88)

                withAnimation(animation) {
                    self.greetingIndex = next
                }

                self.advance(from: next)
            }
        }
    }

    private func enterTour() {
        withAnimation(.easeInOut(duration: 0.6)) {
            stage = .tour
        }
    }

    func skipGreetings() {
        generation += 1
        withAnimation(.easeInOut(duration: 0.5)) {
            stage = .tour
            pageIndex = 0
        }
    }

    // MARK: Tour

    func next() {

        if stage == .greetings {
            skipGreetings()
            return
        }

        if isLastPage {
            close()
            return
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            pageIndex += 1
        }
    }

    func back() {

        guard stage == .tour, pageIndex > 0 else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            pageIndex -= 1
        }
    }

    func close() {
        generation += 1
        onClose?()
    }

    func stop() {
        generation += 1
    }
}

// MARK: - Main view

struct WelcomeView: View {

    @ObservedObject var model: WelcomeModel

    var body: some View {

        ZStack {

            WelcomeBackdrop()

            switch model.stage {
            case .greetings:
                greetingStage
                    .transition(.opacity)
            case .tour:
                tourStage
                    .transition(.opacity)
            }
        }
        .frame(width: WelcomeMetrics.size.width, height: WelcomeMetrics.size.height)
        .clipShape(RoundedRectangle(cornerRadius: WelcomeMetrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WelcomeMetrics.corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(20)
        }
    }

    // MARK: Close

    private var closeButton: some View {
        Button(action: { model.close() }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .welcomeGlass(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    // MARK: Greetings

    private var greetingStage: some View {

        ZStack {

            WelcomeGreetingWheel(index: model.greetingIndex,
                                 visible: model.wheelVisible,
                                 gestureStart: model.gestureStart)
                .offset(y: -10)

            VStack {
                Spacer()
                ZStack {
                    greetingDots
                    HStack {
                        Spacer()
                        Button("Skip") { model.skipGreetings() }
                            .buttonStyle(WelcomeButtonStyle(prominent: false))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var greetingDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<WelcomeGreeting.all.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == model.greetingIndex ? 0.95 : 0.35))
                    .frame(width: i == model.greetingIndex ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.greetingIndex)
    }

    // MARK: Tour

    private var tourStage: some View {

        VStack(spacing: 0) {

            Spacer(minLength: 0)

            WelcomePageView(index: model.pageIndex)
                .id(model.pageIndex)
                .transition(.opacity)
                .frame(height: 390)

            Spacer(minLength: 0)

            bottomBar
                .padding(.bottom, 30)
        }
        .padding(.top, 30)
    }

    private var bottomBar: some View {

        HStack {

            Button(model.pageIndex == 0 ? "Skip" : "Back") {
                if model.pageIndex == 0 {
                    model.close()
                } else {
                    model.back()
                }
            }
            .buttonStyle(WelcomeButtonStyle(prominent: false))
            .frame(width: 130, alignment: .leading)

            Spacer()

            dots

            Spacer()

            Button(nextTitle) { model.next() }
                .buttonStyle(WelcomeButtonStyle(prominent: true))
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.horizontal, 36)
    }

    private var nextTitle: String {
        if model.pageIndex == 0 { return "Start the tour" }
        if model.isLastPage { return "Start using Bevel" }
        return "Next"
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<WelcomeModel.pageCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(i == model.pageIndex ? 0.95 : 0.35))
                    .frame(width: i == model.pageIndex ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.pageIndex)
    }
}

// MARK: - Tour pages

struct WelcomePageView: View {

    let index: Int

    var body: some View {

        VStack(spacing: 24) {

            visual
                .frame(height: 190)

            VStack(spacing: 10) {

                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(message)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 2)
        }
        .padding(.horizontal, 40)
    }

    private var title: String {
        switch index {
        case 0: return "Welcome to Bevel"
        case 1: return "Meet the notch"
        case 2: return "Music and files"
        case 3: return "A tab for everything"
        case 4: return "Make it yours"
        default: return "You're all set"
        }
    }

    private var message: String {
        switch index {
        case 0:
            return "A tiny command center that lives in your Mac's notch. Here is a quick tour; it takes about a minute."
        case 1:
            return "Rest your pointer on the notch and it opens. Move away and it closes again, or pin it to keep it open. A quick sweep across the top of the screen won't trigger it."
        case 2:
            let key = NotchSettings.shared.dragKey.title
            return "Now Playing keeps your music one glance away. To stash a file, hold \(key) while dragging it toward the top of the screen and drop it on the notch. Drag it back out whenever you need it."
        case 3:
            return "Calendar, a clock with alarms and timers, clipboard history, notes, an app launcher and more. Show only the tabs you want."
        case 4:
            return "Press \u{2318}, any time Bevel is active, click the gear in the notch, or use the menu bar icon to open Settings. Choose the notch size, accent colour, hover behaviour, which tabs appear and more."
        default:
            return "macOS may ask for permission the first time you use Calendar, alarms or music controls; that is expected. You can replay this tour from Settings or the menu bar icon."
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch index {
        case 0:
            WelcomeAppIconVisual()
        case 1:
            WelcomeNotchDemo()
        case 2:
            WelcomeDropDemo()
        case 3:
            WelcomeTabGrid()
        case 4:
            WelcomeSettingsVisual()
        default:
            WelcomeDoneVisual()
        }
    }
}

// MARK: - Page visuals

/// First tour page: the app icon floating over soft ripples, with Bevel's tabs
/// orbiting it like tiny glass moons. Tabs behind the icon are smaller and dimmer;
/// tabs in front pass over it, which gives the ring its depth.
struct WelcomeAppIconVisual: View {

    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private let symbols = [
        "music.note", "tray.fill", "calendar", "clock.fill",
        "doc.on.clipboard", "note.text", "square.grid.2x2.fill"
    ]

    private let iconSize: CGFloat = 112
    private let iconCenterY: CGFloat = -8
    private let orbitCenterY: CGFloat = 26
    private let orbitRadiusX: CGFloat = 156
    private let orbitRadiusY: CGFloat = 30

    var body: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in

            let t: Double = reduceMotion ? 0.8 : context.date.timeIntervalSinceReferenceDate

            ZStack {
                glow
                ForEach(0..<3, id: \.self) { k in
                    ripple(index: k, t: t)
                }
                orbit(t: t, front: false)
                icon(t: t)
                orbit(t: t, front: true)
            }
            .frame(width: 440, height: 190)
        }
    }

    // MARK: Pieces

    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.42), Color.white.opacity(0)],
                    center: .center,
                    startRadius: 4,
                    endRadius: 120
                )
            )
            .frame(width: 240, height: 240)
            .offset(y: iconCenterY)
    }

    private func ripple(index: Int, t: Double) -> some View {
        let raw = t * 0.28 + Double(index) / 3.0
        let phase = CGFloat(raw - floor(raw))
        let diameter: CGFloat = 126 + 120 * phase
        let alpha = Double(0.38 * (1 - phase) * (1 - phase))
        return Circle()
            .strokeBorder(Color.white.opacity(alpha), lineWidth: 1.5)
            .frame(width: diameter, height: diameter)
            .offset(y: iconCenterY)
    }

    private func icon(t: Double) -> some View {
        let bob = CGFloat(sin(t * 1.4) * 4)
        return Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: iconSize, height: iconSize)
            .shadow(color: Color(red: 0.05, green: 0.15, blue: 0.55).opacity(0.45), radius: 20, x: 0, y: 12)
            .offset(y: iconCenterY + bob)
            .zIndex(1)
    }

    private func orbit(t: Double, front: Bool) -> some View {
        ZStack {
            ForEach(0..<symbols.count, id: \.self) { i in
                orbitItem(index: i, t: t, front: front)
            }
        }
        .zIndex(front ? 2 : 0)
    }

    @ViewBuilder
    private func orbitItem(index: Int, t: Double, front: Bool) -> some View {

        let angle = t * 0.5 + Double(index) * 2 * Double.pi / Double(symbols.count)
        let sine = CGFloat(sin(angle))
        let cosine = CGFloat(cos(angle))
        let depth = (sine + 1) / 2

        if (sine >= 0) == front {
            Image(systemName: symbols[index])
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .welcomeGlass(Circle())
                .scaleEffect(0.68 + 0.42 * depth)
                .opacity(Double(0.50 + 0.50 * depth))
                .offset(x: cosine * orbitRadiusX, y: orbitCenterY + sine * orbitRadiusY)
        }
    }
}

/// A small looping picture of the notch opening when the pointer rests on it.
struct WelcomeNotchDemo: View {

    static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    static func openAmount(at t: Double) -> Double {
        if t < 1.4 { return 0 }
        if t < 2.1 { return ease((t - 1.4) / 0.7) }
        if t < 4.2 { return 1 }
        if t < 4.9 { return 1 - ease((t - 4.2) / 0.7) }
        return 0
    }

    static func cursorY(at t: Double) -> CGFloat {
        if t < 0.5 { return 100 }
        if t < 1.4 { return 100 - 80 * CGFloat(ease((t - 0.5) / 0.9)) }
        if t < 4.2 { return 20 }
        if t < 5.0 { return 20 + 80 * CGFloat(ease((t - 4.2) / 0.8)) }
        return 100
    }

    private let icons = ["music.note", "tray.fill", "calendar", "clock.fill", "doc.on.clipboard"]

    var body: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in

            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.0)
            let o = CGFloat(WelcomeNotchDemo.openAmount(at: t))
            let notchWidth: CGFloat = 118 + 182 * o
            let notchHeight: CGFloat = 28 + 94 * o

            ZStack(alignment: .top) {

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 400, height: 190)

                // Notch body. It extends above the screen edge so only the bottom corners show.
                RoundedRectangle(cornerRadius: 12 + 10 * o, style: .continuous)
                    .fill(Color.black)
                    .frame(width: notchWidth, height: notchHeight + 16)
                    .offset(x: 0, y: -16)

                notchContent(t: t, open: o)
                    .frame(width: notchWidth, height: notchHeight)

                Image(systemName: "cursorarrow")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 1)
                    .offset(x: 46, y: WelcomeNotchDemo.cursorY(at: t))
            }
            .frame(width: 400, height: 190, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func notchContent(t: Double, open o: CGFloat) -> some View {

        ZStack {

            // Closed look: tiny face on the left, music bars on the right.
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 2.5, height: CGFloat(4 + 8 * abs(sin(t * 5 + Double(i) * 1.3))))
                    }
                }
            }
            .padding(.horizontal, 14)
            .opacity(Double(max(0, 1 - o * 2.5)))

            // Open look: tab row and a seek bar.
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { pair in
                        Image(systemName: pair.element)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(pair.offset == 0 ? 1 : 0.5))
                    }
                }
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 200, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 70, height: 4)
                    }
            }
            .padding(.top, 14)
            .opacity(Double(max(0, (o - 0.55) / 0.45)))
        }
    }
}

/// A looping picture of a file being dropped on the notch.
struct WelcomeDropDemo: View {

    var body: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in

            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5)
            let p = CGFloat(WelcomeNotchDemo.ease(t / 2.0))
            let landed = t > 2.0
            let bump: CGFloat = landed ? CGFloat(max(0, 1 - (t - 2.0) / 0.4)) * 0.10 : 0
            let tileOpacity: Double = t < 2.0 ? 1 : max(0, 1 - (t - 2.0) / 0.25)

            ZStack(alignment: .top) {

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 400, height: 190)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 118, height: 28 + 16)
                    .offset(x: 0, y: -16)
                    .scaleEffect(1 + bump, anchor: .top)

                Image(systemName: "tray.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .offset(x: 0, y: 8)

                Image(systemName: "doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 3)
                    .scaleEffect(1 - 0.65 * p)
                    .opacity(tileOpacity)
                    .offset(x: 0, y: 128 - 118 * p)

                HStack(spacing: 8) {
                    WelcomeKeyCap(label: NotchSettings.shared.dragKey.symbol, side: 34)
                    Text("+ drag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .offset(x: -118, y: 138)
            }
            .frame(width: 400, height: 190, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// Every tab Bevel can show, taken from the real tab list.
struct WelcomeTabGrid: View {

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(NotchTab.allCases) { tab in
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16)
                    Text(tab.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
        }
        .padding(16)
        .frame(width: 540)
        .welcomeGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct WelcomeSettingsVisual: View {

    var body: some View {

        HStack(spacing: 14) {

            WelcomeKeyCap(label: "\u{2318}", side: 64)
            WelcomeKeyCap(label: ",", side: 64)

            Text("or")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 6)

            Image(systemName: "gearshape.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .welcomeGlass(Circle())

            Image(nsImage: BevelMenuBarIcon.image)
                .renderingMode(.template)
                .resizable()
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .welcomeGlass(Circle())
        }
    }
}

struct WelcomeDoneVisual: View {

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Image(systemName: "checkmark")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 124, height: 124)
                .welcomeGlass(Circle())
                .scaleEffect(1 + CGFloat(sin(t * 1.8)) * 0.025)
        }
    }
}

// MARK: - Window

final class WelcomeWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class WelcomeWindowController: NSObject, NSWindowDelegate {

    static let shared = WelcomeWindowController()

    private var window: WelcomeWindow?
    private var model: WelcomeModel?
    private var keyMonitor: Any?

    /// Called at launch: shows the welcome screen only the first time.
    func showIfNeeded() {
        guard !BevelWelcome.hasSeen else { return }
        show()
    }

    /// Shows (or replays) the welcome screen.
    func show() {

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = WelcomeModel()
        model.onClose = { [weak self] in self?.dismiss() }

        let size = WelcomeMetrics.size

        let hosting = NSHostingView(rootView: WelcomeView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        let newWindow = WelcomeWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        newWindow.contentView = hosting
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.delegate = self
        newWindow.center()
        newWindow.alphaValue = 0

        self.window = newWindow
        self.model = model

        installKeyMonitor()

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            newWindow.animator().alphaValue = 1
        }

        model.start()
    }

    /// Fades the window out and closes it.
    private func dismiss() {

        guard let window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    // MARK: Keyboard

    private func installKeyMonitor() {

        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in

            guard let self, let window = self.window, window.isKeyWindow else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let blocked: NSEvent.ModifierFlags = [.command, .option, .control]

            guard flags.isDisjoint(with: blocked) else { return event }

            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {

        guard let model else { return false }

        switch event.keyCode {
        case 53:            // esc
            model.close()
            return true
        case 124, 36, 76, 49:   // right arrow, return, enter, space
            model.next()
            return true
        case 123:           // left arrow
            model.back()
            return true
        default:
            return false
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {

        BevelWelcome.markSeen()

        model?.stop()

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }

        keyMonitor = nil
        window?.delegate = nil
        window = nil
        model = nil
    }
}
