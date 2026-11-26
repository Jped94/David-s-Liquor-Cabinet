import CellarKit
import SwiftUI

/// Shown after a sync: what was added, what changed, what's gone.
struct SyncReportView: View {
    let report: SyncReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sync Report")
                            .font(Theme.display(38))
                            .foregroundStyle(Theme.ink)
                        Text(summary)
                            .font(Theme.italic(19))
                            .foregroundStyle(Theme.muted)
                    }

                    if report.isInitial {
                        Text("The collection is now coming from CellarTracker. Future syncs will list what changed.")
                            .font(Theme.body(19))
                            .foregroundStyle(Theme.ink)
                    } else if !report.hasChanges {
                        Text("Nothing has changed since the last sync.")
                            .font(Theme.body(19))
                            .foregroundStyle(Theme.ink)
                    } else {
                        group("New to the collection", report.added) { change in
                            change.after == 1 ? "1 bottle" : "\(change.after) bottles"
                        }
                        group("More bottles", report.increased) { "\($0.before) → \($0.after)" }
                        group("Fewer bottles", report.decreased) { "\($0.before) → \($0.after)" }
                        group("Gone", report.removed) { change in
                            change.before == 1 ? "was 1 bottle" : "was \(change.before) bottles"
                        }
                    }
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.card.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Theme.body(18, .semibold))
                }
            }
            .toolbarBackground(Theme.card, for: .navigationBar)
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.card)
    }

    private var summary: String {
        let date = report.date.formatted(date: .abbreviated, time: .shortened)
        return "\(date) · \(report.productCount) products · \(report.bottleCount) bottles"
    }

    @ViewBuilder
    private func group(_ title: String, _ changes: [SyncReport.Change], detail: @escaping (SyncReport.Change) -> String) -> some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "\(title) (\(changes.count))")
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .lastTextBaseline, spacing: 8) {
                            Text(change.title)
                                .font(Theme.body(20, .medium))
                                .foregroundStyle(Theme.ink)
                                .layoutPriority(1)
                            DottedLeader()
                            Text(detail(change))
                                .font(Theme.body(17))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Text([change.subtitle, change.category.displayName].compactMap { $0 }.joined(separator: " · "))
                            .font(Theme.italic(16))
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
