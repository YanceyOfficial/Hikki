#if os(iOS)
    import Synchronization
    import SwiftUI
    import UIKit

    /// The phone's slide-out drawer (Notion's, exodus-ios's `SideDrawer`): the content is a rounded card pushed to the
    /// right over a sidebar, dimmed toward its own background while the sidebar shows. iOS has no phone drawer, so the
    /// container is custom; what goes in it is plain SwiftUI. A horizontal drag anywhere opens or closes it (a UIKit pan
    /// that arbitrates with scroll views — see `DrawerPan`), ☰ toggles it through `isOpen`, a tap on the card closes it.
    /// It fills the screen and hands the container insets on to the card and the sidebar as safe area.
    public struct SideDrawer<Sidebar: View, Content: View>: View {
        @Binding private var isOpen: Bool
        private let closeLabel: LocalizedStringKey
        private let sidebar: () -> Sidebar
        private let content: () -> Content

        /// The card's offset while a drag is in flight, nil otherwise. Plain `@State`, not `@GestureState`: that one
        /// resets before the release is handled, which drew the card one frame at its old place.
        @State private var drag: CGFloat?
        /// Where the card was on screen when the finger landed, so catching it mid-settle picks it up where it is.
        @State private var dragStart: CGFloat = 0
        @State private var liveOffset = DrawerLiveOffset()
        /// Bumped when letting go of the card changes whether it is open — the one haptic tap.
        @State private var releases = 0
        /// The sidebar is in the hierarchy only while it can be seen: from the moment the drawer opens or a drag starts
        /// until the card has covered it again.
        @State private var showsSidebar = false
        /// The screen's container insets, measured behind the drawer.
        @State private var insets = EdgeInsets()
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme

        /// - Parameters:
        ///   - isOpen: whether the sidebar shows; set it inside `withAnimation(Motion.easeOut())` to slide it.
        ///   - closeLabel: the VoiceOver name of the card while it closes the drawer on a tap.
        public init(
            isOpen: Binding<Bool>, closeLabel: LocalizedStringKey, @ViewBuilder sidebar: @escaping () -> Sidebar,
            @ViewBuilder content: @escaping () -> Content
        ) {
            _isOpen = isOpen
            self.closeLabel = closeLabel
            self.sidebar = sidebar
            self.content = content
        }

        public var body: some View {
            // The card and the sidebar fill the screen and hand the container insets (status bar, home indicator) on
            // to what is inside as safe area. The keyboard's is left to SwiftUI, which the drawer never ignores, so a
            // field in the card still rises with the keyboard.
            drawer(insets: insets)
                .ignoresSafeArea(.container)
                .background {
                    Color.clear
                        .onGeometryChange(for: EdgeInsets.self, of: \.safeAreaInsets) { insets = $0 }
                        .ignoresSafeArea(.keyboard)
                }
        }

        private func drawer(insets: EdgeInsets) -> some View {
            GeometryReader { geo in
                let drawerWidth = DrawerPhysics.width(for: geo.size.width)
                let offset = drag ?? (isOpen ? drawerWidth : 0)
                let progress = drawerWidth > 0 ? min(max(offset / drawerWidth, 0), 1) : 0
                // The display's own corner radii (the reader fills the screen), so the closed card's corners sit under
                // the glass's; a display that reports none gets the fallback.
                let displayRadius: CGFloat =
                    if #available(iOS 27.0, *) { geo.concentricCornerRadii?.bottomLeading ?? 0 } else { 0 }
                let cardRadius = displayRadius > 0 ? displayRadius : Radius.xl + Spacing.s3
                // The sidebar arrives ahead of the card and is fully there when the card lands.
                let reveal = min(1, progress * 1.5)

                ZStack(alignment: .leading) {
                    if showsSidebar {
                        sidebarLayer(width: drawerWidth, reveal: reveal)
                    }

                    content()
                        .safeAreaPadding(insets)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Theme.background)
                        // Dims toward the card's own background, never toward black, so dark mode keeps its depth.
                        .overlay {
                            Theme.background.opacity(0.6 * progress).allowsHitTesting(false)
                        }
                        .clipShape(.rect(cornerRadius: cardRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                                .strokeBorder(Theme.border.opacity(colorScheme == .dark ? progress : 0), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                        .shadow(color: .black.opacity(0.15 * progress), radius: Spacing.s6, x: -Spacing.s1)
                        .modifier(DrawerCardOffset(offset: offset, live: liveOffset))
                        .accessibilityHidden(isOpen)

                    if isOpen {
                        // The tap target over the card: one VoiceOver button that closes the drawer.
                        Color.clear
                            .frame(width: geo.size.width, height: geo.size.height)
                            .contentShape(.rect)
                            .offset(x: offset)
                            .onTapGesture { setOpen(false) }
                            .accessibilityElement()
                            .accessibilityLabel(Text(closeLabel))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { setOpen(false) }
                            .accessibilityIdentifier("drawer-close")
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // A rotation moves the card without animating it, behind the sampler's back.
                .onChange(of: drawerWidth) { _, _ in liveOffset.value = offset }
                .gesture(
                    DrawerPan(
                        isOpen: isOpen,
                        onBegin: {
                            showsSidebar = true
                            dragStart = liveOffset.value
                        },
                        onChange: { travel in
                            drag = DrawerPhysics.resistedOffset(dragStart + travel, drawerWidth: drawerWidth)
                        },
                        onRelease: { travel, velocity in
                            let landed = DrawerPhysics.resistedOffset(dragStart + travel, drawerWidth: drawerWidth)
                            let open = DrawerPhysics.endsOpen(offset: landed, velocity: velocity, drawerWidth: drawerWidth)
                            if open != isOpen { releases += 1 }
                            settle(open: open)
                        },
                        // Cancelled by the system: no velocity to speak of, it settles by where it stands.
                        onCancel: {
                            guard let pending = drag else { return }
                            settle(open: pending > drawerWidth / 2)
                        }
                    )
                )
                .accessibilityAction(.escape) { setOpen(false) }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: releases)
            .onChange(of: isOpen, initial: true) { _, nowOpen in
                if nowOpen {
                    showsSidebar = true
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } else {
                    hideSidebarWhenCovered()
                }
            }
        }

        /// Takes the sidebar out once the card has covered it: nothing invisible stays for VoiceOver or the hit test.
        private func hideSidebarWhenCovered() {
            Task {
                try? await Task.sleep(for: .seconds(Motion.popIn))
                if !isOpen, drag == nil { showsSidebar = false }
            }
        }

        private func sidebarLayer(width: CGFloat, reveal: CGFloat) -> some View {
            sidebar()
                .safeAreaPadding(insets)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                // Fades in and grows from the leading edge as the card uncovers it (no growing under Reduce Motion: the
                // fade says the same).
                .opacity(reveal)
                .scaleEffect(reduceMotion ? 1 : 0.92 + 0.08 * reveal, anchor: .leading)
                .background(Theme.sidebar)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
                .transition(.identity)
        }

        private func setOpen(_ open: Bool) {
            withAnimation(Motion.easeOut()) { isOpen = open }
        }

        /// Ends a drag: the resting place and the end of the drag are one change, so the card goes straight from where
        /// it is on screen to where it belongs. The strong ease-out starts fast, which carries a flick on.
        private func settle(open: Bool) {
            withAnimation(Motion.easeOut()) {
                isOpen = open
                drag = nil
            }
            // A drag that fell back closed leaves `isOpen` as it was, so its change never fires.
            if !open { hideSidebarWhenCovered() }
        }
    }

    /// The drawer's numbers, free of SwiftUI and UIKit (exodus-ios's `DrawerPhysics`). The card's offset runs from 0
    /// (closed) to the drawer's width (open); the closed end is a hard wall, the open end rubber-bands.
    public enum DrawerPhysics {
        /// Most of the screen, never wider than `Size.drawer` (a landscape phone, an iPad window).
        public static func width(for screen: CGFloat) -> CGFloat { min(screen * 0.85, Size.drawer) }

        /// UIScrollView's deceleration rate, used to project where a flick is heading.
        static let decelerationRate: CGFloat = 0.998

        /// How much further a release at `velocity` (points per second) would travel before friction stops it.
        public static func project(velocity: CGFloat) -> CGFloat {
            (velocity / 1000) * decelerationRate / (1 - decelerationRate)
        }

        /// How far past a boundary something follows the finger: less and less, never more than `dimension`.
        public static func rubberBand(overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
            guard dimension > 0 else { return 0 }
            return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
        }

        /// The card's offset for the one the finger asks for: 1:1 between the ends, a stop at closed, a band past open.
        public static func resistedOffset(_ wanted: CGFloat, drawerWidth: CGFloat) -> CGFloat {
            guard drawerWidth > 0, wanted > 0 else { return 0 }
            if wanted <= drawerWidth { return wanted }
            return drawerWidth + rubberBand(overshoot: wanted - drawerWidth, dimension: drawerWidth)
        }

        /// Where a release lands: the finger's momentum projected forward, the nearer resting place wins — a quick
        /// flick from 10 pt opens, a slow drag two thirds of the way back falls closed.
        public static func endsOpen(offset: CGFloat, velocity: CGFloat, drawerWidth: CGFloat) -> Bool {
            offset + project(velocity: velocity) > drawerWidth / 2
        }

        /// How long after the last touch event a release still counts as moving, in seconds: a finger that stopped
        /// sends no events and UIKit keeps reporting its last speed.
        static let velocityStaleAfter: Double = 0.1
    }

    /// The drawer's drag: a UIKit pan behind SwiftUI, because SwiftUI's `DragGesture` cannot say "this touch is not
    /// mine". `gestureRecognizerShouldBegin` decides once, from the movement so far: horizontal only, rightward when
    /// closed and leftward when open; vertical drags stay the scroll view's. A horizontal scroll view (Jump back in)
    /// keeps a drag that starts on it unless it sits at its leading edge, where a rightward drag opens the drawer.
    private struct DrawerPan: UIGestureRecognizerRepresentable {
        let isOpen: Bool
        let onBegin: () -> Void
        let onChange: (CGFloat) -> Void
        let onRelease: (CGFloat, CGFloat) -> Void
        let onCancel: () -> Void

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            var isOpen = false

            func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
                guard let pan = recognizer as? DrawerPanRecognizer else { return false }
                let movement = pan.movementSinceTouchDown
                guard abs(movement.x) > abs(movement.y) else { return false }
                if isOpen { return movement.x < 0 }
                guard movement.x > 0 else { return false }
                // A horizontal list scrolled away from its start scrolls back first.
                if let scroll = pan.horizontalScrollView, !scroll.isAtLeadingEdge { return false }
                return true
            }

            /// A horizontal scroll view under the finger waits for the drawer to decline, so at its leading edge a
            /// rightward drag is the drawer's and everything else is the list's.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer
            ) -> Bool {
                guard let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer else { return false }
                return scroll.scrollsHorizontally && (recognizer as? DrawerPanRecognizer)?.horizontalScrollView === scroll
            }
        }

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

        func makeUIGestureRecognizer(context: Context) -> DrawerPanRecognizer {
            let pan = DrawerPanRecognizer()
            pan.delegate = context.coordinator
            return pan
        }

        func updateUIGestureRecognizer(_ recognizer: DrawerPanRecognizer, context: Context) {
            context.coordinator.isOpen = isOpen
        }

        func handleUIGestureRecognizerAction(_ recognizer: DrawerPanRecognizer, context: Context) {
            // UIKit's ~10 pt of hysteresis is already out of `translation`: the card moves point for point from there.
            let travel = recognizer.translation(in: recognizer.view).x
            switch recognizer.state {
            case .began:
                onBegin()
                onChange(travel)
            case .changed: onChange(travel)
            case .ended: onRelease(travel, recognizer.releaseVelocity.x)
            case .cancelled, .failed: onCancel()
            default: break
            }
        }
    }

    /// Slides the card and writes down where it is drawn: `Animatable` sees every frame's interpolated value, which
    /// `onGeometryChange` never does for an `.offset`.
    private struct DrawerCardOffset: ViewModifier, Animatable {
        var offset: CGFloat
        let live: DrawerLiveOffset

        nonisolated var animatableData: CGFloat {
            get { offset }
            set {
                offset = newValue
                live.value = max(0, newValue)
            }
        }

        func body(content: Content) -> some View {
            content.offset(x: max(0, offset))
        }
    }

    /// Where the card is on screen. Not observable (it changes every frame and only the next drag reads it) and not
    /// actor-isolated (`Animatable` writes it from SwiftUI's update pass), hence the mutex.
    nonisolated private final class DrawerLiveOffset: Sendable {
        private let storage = Mutex<CGFloat>(0)

        var value: CGFloat {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }

    /// A pan that remembers where the finger landed (the direction is judged from the whole movement, hysteresis
    /// included), which horizontal scroll view it landed on, and whether its velocity is still fresh.
    private final class DrawerPanRecognizer: UIPanGestureRecognizer {
        private var touchDown: CGPoint?
        private var lastEvent: CFTimeInterval = 0
        private(set) weak var horizontalScrollView: UIScrollView?

        var movementSinceTouchDown: CGPoint {
            guard let touchDown, let view else { return .zero }
            let now = location(in: view)
            return CGPoint(x: now.x - touchDown.x, y: now.y - touchDown.y)
        }

        /// The release speed, or none when the finger had stopped before letting go.
        var releaseVelocity: CGPoint {
            guard CACurrentMediaTime() - lastEvent < DrawerPhysics.velocityStaleAfter else { return .zero }
            return velocity(in: view)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if touchDown == nil, let first = touches.first {
                touchDown = first.location(in: view)
                var hit = first.view
                while let candidate = hit, (candidate as? UIScrollView)?.scrollsHorizontally != true {
                    hit = candidate.superview
                }
                horizontalScrollView = hit as? UIScrollView
            }
            super.touchesBegan(touches, with: event)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            lastEvent = CACurrentMediaTime()
            super.touchesMoved(touches, with: event)
        }

        override func reset() {
            super.reset()
            touchDown = nil
            lastEvent = 0
            horizontalScrollView = nil
        }
    }

    extension UIScrollView {
        fileprivate var scrollsHorizontally: Bool {
            contentSize.width > bounds.width - adjustedContentInset.left - adjustedContentInset.right + 1
        }

        fileprivate var isAtLeadingEdge: Bool { contentOffset.x <= -adjustedContentInset.left + 0.5 }
    }

    #Preview {
        @Previewable @State var isOpen = true
        SideDrawer(isOpen: $isOpen, closeLabel: "Close sidebar") {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(verbatim: "Workspace").font(.hk(.lg, .semibold))
                ForEach(["Getting started", "Reading list", "Trip to Kyoto"], id: \.self) { title in
                    Text(verbatim: title).font(.hk(.base))
                }
                Spacer()
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } content: {
            VStack(spacing: Spacing.s4) {
                Button {
                    withAnimation(Motion.easeOut()) { isOpen.toggle() }
                } label: {
                    IconView(.list, size: TextSize.xl.rawValue)
                }
                Text(verbatim: "Home").font(.hk(.x2l, .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
#endif
