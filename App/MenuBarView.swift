import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let d = model.derived
        VStack(alignment: .leading, spacing: 12) {
            if !d.rings.isEmpty {
                HStack(spacing: 10) { ForEach(d.rings) { RingView(ring: $0, size: 48, line: 5) } }
            }
            if let r = d.nextRun {
                HStack(spacing: 6) {
                    Image(systemName: r.kind.symbol).foregroundStyle(r.kind.color)
                    Text("\(Fmt.relativeDay(r.date)): \(r.shortTitle)" + (r.miles.map { " · \(Fmt.miles($0)) mi" } ?? ""))
                }
                .font(.callout)
            }
            if let p = d.predicted {
                Text("Predicted half \(Fmt.hms(p))" + (d.gapToGoal.map { $0 > 0 ? " · \(Fmt.hms($0)) to goal" : " · under goal!" } ?? ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Open app") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
                Button("Refresh") { Task { await model.refresh() } }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
