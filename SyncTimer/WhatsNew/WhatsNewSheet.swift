import SwiftUI

struct WhatsNewSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entry: WhatsNewVersionEntry
    let onAction: (WhatsNewAction) -> Void
    let onDismiss: () -> Void

    @State private var showReleaseNotes = false
    @State private var drawSymbols = false

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
        .onAppear {
            guard !reduceMotion else { return }
            drawSymbols = true
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
        }
        .padding(.top, 4)
    }

    private func bulletRow(_ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
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
        HStack(alignment: .top, spacing: 12) {
            featureIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.headline)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(card.ctaTitle) {
                    WhatsNewHaptics.triggerIfPhone()
                    onAction(card.ctaAction)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground)
    }

    private var featureIcon: some View {
        let image = Image(systemName: card.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.accentColor)
            .symbolRenderingMode(.hierarchical)
            .accessibilityHidden(true)

        if #available(iOS 26.0, *), reduceMotion == false {
            image.symbolEffect(.drawOn, options: .speed(1.2), value: drawSymbols)
        } else {
            image
        }
    }

    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            ForEach(entry.bullets ?? [], id: \.self) { bullet in
                Label {
                    Text(bullet)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
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
