import SwiftUI
import NookCore

struct WidgetPreviewView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("widgets.details") private var details = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Preview uses this phone's data. If a Home Screen widget shows no data, check the sharing status in Settings.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                Toggle("Show Details in Widgets", isOn: $details)
                    .onChange(of: details) { _, _ in WidgetPublisher.publish(store) }
                ForEach(NookWidgetContentKind.allCases) { kind in
                    NookWidgetContent(kind: kind, data: .ready(snapshot), medium: true)
                        .padding(16).frame(height: 170)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("widget.preview.\(kind.rawValue)")
                }
            }.padding(Metrics.screenPadding)
        }
        .background(Theme.background).navigationTitle("Widget Previews")
        .navigationBarTitleDisplayMode(.inline)
    }
    private var snapshot: WidgetSnapshot {
        .make(notes: store.notes, events: store.events, trips: store.trips, tasks: store.tasks,
              anniversaries: store.anniversaries, details: details, timeZone: store.timeZone)
    }
}
