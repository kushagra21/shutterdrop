import ShutterdropCore
import SwiftUI

/// What a date adjustment can apply to, and the photo used to set the time.
struct DateAdjustment: Identifiable {
    let id = UUID()
    let reference: Shot
    let selected: [Shot]
    let day: URL
    let dayShots: [Shot]
}

/// Fix photos taken with a wrong camera clock: say when one photo was really
/// taken, and the same shift is applied to the others.
struct AdjustDatesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let adjustment: DateAdjustment

    enum Scope: Hashable { case photo, selection, day }

    @State private var actual = Date()
    @State private var scope = Scope.day

    private var cameraTime: Date { adjustment.reference.captured ?? Date() }
    private var offset: TimeInterval { actual.timeIntervalSince(cameraTime).rounded() }

    private var targets: [Shot] {
        switch scope {
        case .photo: [adjustment.reference]
        case .selection: adjustment.selected
        case .day: adjustment.dayShots
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust Dates").font(.title2.bold())
            Text("For photos taken while the camera's clock was wrong. Set when this photo was really taken; the same shift is applied to the others.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 14) {
                PhotoImage(url: adjustment.reference.displayURL)
                    .frame(width: 150, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Grid(alignment: .leading, verticalSpacing: 10) {
                    GridRow {
                        Text("Camera clock").foregroundStyle(.secondary)
                        Text(cameraTime.formatted(date: .abbreviated, time: .standard))
                    }
                    GridRow {
                        Text("Actually taken").foregroundStyle(.secondary)
                        DatePicker("Actually taken", selection: $actual, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    GridRow {
                        Text("Shift").foregroundStyle(.secondary)
                        Text(Self.describe(offset)).monospacedDigit()
                    }
                }
            }

            Picker("Apply to", selection: $scope) {
                Text("This photo").tag(Scope.photo)
                if adjustment.selected.count > 1 {
                    Text("Selected photos (\(adjustment.selected.count))").tag(Scope.selection)
                }
                Text("All photos on \(ContentView.dayTitle(adjustment.day)) (\(adjustment.dayShots.count))").tag(Scope.day)
            }
            .pickerStyle(.radioGroup)

            Text("This moves photos to the right day in Shutterdrop's folder and corrects their file dates. The date stored inside the files (EXIF) stays as the camera wrote it; Lightroom and Photos can change that too.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Adjust \(targets.count) Photo\(targets.count == 1 ? "" : "s")") {
                    model.applyDateShift(targets, by: offset, reference: adjustment.reference)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(offset == 0)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            actual = cameraTime
            scope = adjustment.selected.count > 1 ? .selection : .day
        }
    }

    /// "−30 days 0 h 9 min 0 s", or "none".
    static func describe(_ offset: TimeInterval) -> String {
        guard offset != 0 else { return "none" }
        var rest = Int(abs(offset))
        let days = rest / 86_400; rest %= 86_400
        let hours = rest / 3_600; rest %= 3_600
        let minutes = rest / 60
        let seconds = rest % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) day\(days == 1 ? "" : "s")") }
        if hours > 0 || days > 0 { parts.append("\(hours) h") }
        parts.append("\(minutes) min")
        if seconds > 0 { parts.append("\(seconds) s") }
        return (offset < 0 ? "−" : "+") + parts.joined(separator: " ")
    }
}
