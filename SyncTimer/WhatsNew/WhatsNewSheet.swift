import SwiftUI

enum ReleaseNotes {
    static let url = URL(string: "https://www.synctimerapp.com/release-notes")!
}

struct WhatsNewSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onJoinNow: () -> Void
    let onOpenCueSheets: () -> Void
    let onTestSync: () -> Void
    let onViewReleaseNotes: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                ScrollView { sheetContent }
                    .scrollIndicators(.hidden)
            } else {
                ScrollView { sheetContent }
            }
        }
        .background(Color.clear)
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text("What’s New in SyncTimer")
                .font(.title2.weight(.semibold))
            Text("Version 0.9")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Faster joining, richer cue sheets, tighter sync.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var featureCards: some View {
        VStack(spacing: 12) {
            FeatureCard(
                icon: "qrcode.viewfinder",
                title: "Join a room in seconds",
                detail: "Scan a QR or open a join link to connect instantly.",
                cta: "Join now",
                onTap: onJoinNow,
                reduceMotion: reduceMotion
            )
            FeatureCard(
                icon: "text.bubble",
                title: "Cue sheets can show messages + images",
                detail: "Push on-screen text or images as part of the cue timeline.",
                cta: "Open Cue Sheets",
                onTap: onOpenCueSheets,
                reduceMotion: reduceMotion
            )
            FeatureCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "More reliable Nearby sync",
                detail: "Better sequencing and stop accuracy under BLE congestion.",
                cta: "Test Sync",
                onTap: onTestSync,
                reduceMotion: reduceMotion
            )
        }
    }

    private var moreImprovements: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                bullet("Asset-aware cue transport (children can request missing images)")
                bullet("Room labels / saved rooms support")
                bullet("Cue sheet XML v2 support (richer events)")
                bullet("Cue badge label derives from library (less stale UI)")
                bullet("UI refinements (glass buttons, editor polish)")
                bullet("Join flows + handoff improvements")
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

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .labelStyle(.titleAndIcon)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button("View full release notes") {
                onViewReleaseNotes()
            }
            .buttonStyle(.bordered)

            Button("Not now") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var glassContainer: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let detail: String
    let cta: String
    let onTap: () -> Void
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            featureIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(cta) {
                    onTap()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackground)
    }

    @ViewBuilder
    private var featureIcon: some View {
        let image = Image(systemName: icon)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.accentColor)
            .symbolRenderingMode(.hierarchical)

        if #available(iOS 26.0, *), reduceMotion == false {
            image.symbolEffect(.drawOn)
        } else {
            image
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
