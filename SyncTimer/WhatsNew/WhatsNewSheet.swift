import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WhatsNewSheet: View {
    @State private var didKickDraw = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: WhatsNewVersionEntry
    let onAction: (WhatsNewAction) -> Void
    let onDismiss: () -> Void

    @State private var showReleaseNotes = false
    @State private var drawSymbols = false   // pulse true briefly to run draw-on

    var body: some View {
        NavigationStack {
            ScrollView {
                sheetContent
            }
            .scrollIndicators(.hidden)
            .background(Color.clear)
            .navigationDestination(isPresented: $showReleaseNotes) {
                ReleaseNotesView(entry: entry)
            }
        }
        .task {
            guard reduceMotion == false else { return }
            guard didKickDraw == false else { return }
            didKickDraw = true

            drawSymbols = false
            try? await Task.sleep(nanoseconds: 80_000_000)   // let views mount
            drawSymbols = true                               // triggers drawOn
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            drawSymbols = false                              // hide overlay (base stays)
        }

    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            featureCards
            moreImprovements
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(glassContainer)
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.subtitle)
                .font(.headline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.lede)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureCards: some View {
        VStack(spacing: 12) {
            ForEach(entry.cards) { card in
                FeatureCard(
                    card: card,
                    reduceMotion: reduceMotion,
                    drawSymbols: drawSymbols,
                    onAction: handleAction
                )
            }
        }
    }

    private var moreImprovements: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.bullets ?? [], id: \.self) { bullet in
                    bulletRow(bullet)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 6)
        } label: {
            Text("More improvements")
                .font(.headline)
                .foregroundStyle(.black)
        }
        .padding(.top, 4)
    }

    private func bulletRow(_ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.tint, .tint.opacity(0.28))
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button("Release Notes") {
                showReleaseNotes = true
            }
            .buttonStyle(.bordered)

            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var glassContainer: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
        }
    }

    private func handleAction(_ action: WhatsNewAction) {
        if action == .openReleaseNotes {
            showReleaseNotes = true
            return
        }
        onAction(action)
    }
}

private struct FeatureCard: View {

    let card: WhatsNewCard
    let reduceMotion: Bool
    let drawSymbols: Bool
    let onAction: (WhatsNewAction) -> Void

    var body: some View {
        Button {
            WhatsNewHaptics.triggerIfPhone()
            onAction(card.ctaAction)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                featureIcon
                    .padding(.leading, 2)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(card.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(card.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .padding(12)
            .background(cardBackground)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(card.ctaTitle)
    }


    @ViewBuilder
    private var featureIcon: some View {
        let base = Image(systemName: resolvedSymbolName)
            .font(.system(size: 44, weight: .semibold))
            .symbolRenderingMode(.palette)
            // Two explicit layers: always colored (and “multicolor-ish” on multi-layer symbols).
            .foregroundStyle(.tint, .tint.opacity(0.28))
            .accessibilityHidden(true)

        let overlay = Image(systemName: resolvedSymbolName)
            .font(.system(size: 44, weight: .semibold))
            // Keep draw-on overlay single-color so the stroke is legible.
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)

        ZStack {
            base

            // Only render overlay while animating; otherwise it masks the base and you see "gray -> black".
            if #available(iOS 26.0, *), reduceMotion == false, drawSymbols {
                overlay
                    .opacity(drawSymbols ? 1 : 0) // so it never masks the base when idle
                    .animation(.none, value: drawSymbols)
                    .symbolEffect(.drawOn, options: .speed(1.10), isActive: drawSymbols)
                    .allowsHitTesting(false)

            }
        }
        .frame(width: 60, height: 60, alignment: .topLeading)
    }


    private var resolvedSymbolName: String {
        let trimmed = card.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? "sparkles" : trimmed
#if DEBUG && canImport(UIKit)
        assert(UIImage(systemName: resolvedName) != nil, "Invalid SF Symbol: \(resolvedName)")
#endif
#if canImport(UIKit)
        if UIImage(systemName: resolvedName) == nil {
            return "sparkles"
        }
#endif
        return resolvedName
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        } else {
            shape
                .fill(.thinMaterial)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct ReleaseNotesView: View {
    let entry: WhatsNewVersionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                cards
                improvements
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Release Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.subtitle)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(entry.lede)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entry.cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.headline)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(cardBackground)
            }
        }
    }

    private var improvements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More improvements")
                .font(.headline)
                .foregroundStyle(.black)

            ForEach(entry.bullets ?? [], id: \.self) { bullet in
                Label {
                    Text(bullet)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.tint, .tint.opacity(0.28))
                        .accessibilityHidden(true)
                }
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                shape
                    .fill(.thinMaterial)
                    .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }
}

private enum WhatsNewHaptics {
    static func triggerIfPhone() {
        #if canImport(UIKit)
        if UIDevice.current.userInterfaceIdiom == .phone {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
}
