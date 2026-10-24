import ShutterdropCore
import SwiftUI

/// Walks through a Send to Computer import: wait, connect, read the card,
/// confirm, copy. A checklist and elapsed time show it's working throughout.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Import Full-Size Files").font(.title2.bold())
                Spacer()
                if model.importState.isActive, let started = model.importStartedAt {
                    ElapsedTime(since: started)
                }
            }
            content
            Spacer(minLength: 0)
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 480, height: 400)
        .interactiveDismissDisabled(model.importState.isActive)
    }

    @ViewBuilder private var content: some View {
        @Bindable var model = model
        switch model.importState {
        case .idle:
            Text("Copies the full-size files from the camera over your home Wi-Fi and pairs them with the live previews.")
            Picker("Photos to import", selection: $model.importRange) {
                ForEach(AppModel.ImportRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text("Files already in the library are skipped. Dates follow the camera's clock.")
                .font(.callout).foregroundStyle(.secondary)
        case .waiting, .connecting, .reading:
            ImportSteps(state: model.importState)
        case let .confirm(files):
            ImportSteps(state: model.importState)
            confirmation(files)
        case let .copying(index, count, name):
            ImportSteps(state: model.importState)
            ProgressView(value: Double(index), total: Double(count)) {
                Text("Copied \(index) of \(count)")
            } currentValueLabel: {
                Text(name)
            }
            Text("Keep the camera on and near the router. Cancel stops after the current file; the next import carries on from there.")
                .font(.callout).foregroundStyle(.secondary)
        case let .done(count):
            Label(count == 0 ? "Nothing new to import." : "Copied \(count) file(s).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.title3)
            if count > 0 {
                Text("The camera saves and switches itself off.").foregroundStyle(.secondary)
            }
        case let .failed(message):
            Label("Import stopped", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
            Text(message).textSelection(.enabled)
            Text("Already-copied files are kept; importing again continues where it stopped.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.importState {
        case .idle:
            Button("Cancel", role: .cancel) { model.finishImportSheet() }
            Button("Start") { model.startImport() }.keyboardShortcut(.defaultAction)
        case .confirm:
            Button("Cancel", role: .cancel) { model.confirmImport(false) }
            Button("Import") { model.confirmImport(true) }.keyboardShortcut(.defaultAction)
        case .done:
            Button("Done") { model.finishImportSheet() }.keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close") { model.finishImportSheet() }
            Button("Try Again") { model.startImport() }.keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { model.cancelImport() }
        }
    }

    private func confirmation(_ files: [PendingFile]) -> some View {
        let bytes = files.reduce(0) { $0 + $1.size }
        let dates = files.compactMap(\.captured)
        // Measured on the A7 III: ~1.2 MB/s at first, slower on long imports.
        let minutes = max(1, Int((Double(bytes) / 1_000_000 / 60).rounded(.up)))
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(files.count) new file(s), \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                .font(.headline)
            if let first = dates.min(), let last = dates.max() {
                Text("Taken \(first.formatted(date: .abbreviated, time: .shortened)) – \(last.formatted(date: .abbreviated, time: .shortened)) (camera clock)")
            }
            Text("About \(minutes) min or more over Wi-Fi.").foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

/// The import steps with a tick for each one done and a spinner on the current one.
struct ImportSteps: View {
    let state: AppModel.ImportState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(1, "Waiting for the camera",
                detail: "Mac on home Wi-Fi; on the camera choose MENU → Network → Send to Computer.")
            row(2, connectingTitle, detail: connectingDetail)
            row(3, readingTitle, detail: state.step == 3 ? "The camera answers one file at a time; this takes a while over Wi-Fi." : nil)
            if case let .reading(done, total) = state, total > 0 {
                ProgressView(value: Double(done), total: Double(total)).padding(.leading, 28)
            }
            row(4, "Choose what to copy", detail: nil)
            row(5, "Copy files", detail: nil)
        }
    }

    private var connectingTitle: String {
        if case let .connecting(host, _) = state { return "Connecting to the camera at \(host)" }
        return "Connecting to the camera"
    }

    private var connectingDetail: String? {
        guard case let .connecting(_, attempt) = state else { return nil }
        return attempt > 1
            ? "Camera found; it's still opening its connection (attempt \(attempt))…"
            : "Camera found. It should show \"Sending… Shutterdrop\"."
    }

    private var readingTitle: String {
        if case let .reading(done, total) = state, total > 0 { return "Reading the camera's card (\(done) of \(total))" }
        return "Reading the camera's card"
    }

    @ViewBuilder private func row(_ step: Int, _ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if state.step > step {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if state.step == step {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(state.step >= step ? .primary : .secondary)
                    .fontWeight(state.step == step ? .semibold : .regular)
                if let detail, state.step == step {
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// "0:42" counting up, so a long wait still looks alive.
struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            Label(String(format: "%d:%02d", seconds / 60, seconds % 60), systemImage: "clock")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
