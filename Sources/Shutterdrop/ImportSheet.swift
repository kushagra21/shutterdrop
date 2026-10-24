import ShutterdropCore
import SwiftUI

/// Walks through a Send to Computer import: wait, read the card, confirm, copy.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Full-Size Files").font(.title2.bold())
            content
            Spacer(minLength: 0)
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 460, height: 340)
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
        case .waiting:
            step("Waiting for the camera…", detail: "Make sure this Mac is on your home Wi-Fi, then on the camera choose MENU → Network → Send to Computer.")
        case let .connecting(host):
            step("Connecting to the camera at \(host)…", detail: "The camera should show \"Sending… Shutterdrop\".")
        case .reading:
            step("Reading the camera's card…", detail: "This takes about 20 seconds over Wi-Fi.")
        case let .confirm(files):
            confirmation(files)
        case let .copying(index, count, name):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(index), total: Double(count)) {
                    Text("Copied \(index) of \(count)")
                } currentValueLabel: {
                    Text(name)
                }
                Text("Keep the camera on and near the router. Cancel stops after the current file; the next import carries on from there.")
                    .font(.callout).foregroundStyle(.secondary)
            }
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

    private func step(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(title).font(.headline)
            }
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func confirmation(_ files: [PendingFile]) -> some View {
        let bytes = files.reduce(0) { $0 + $1.size }
        let dates = files.compactMap(\.captured)
        // Measured on the A7 III: ~1.2 MB/s at first, slower on long imports.
        let minutes = max(1, Int((Double(bytes) / 1_000_000 / 1.0 / 60).rounded(.up)))
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(files.count) new file(s), \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                .font(.headline)
            if let first = dates.min(), let last = dates.max() {
                Text("Taken \(first.formatted(date: .abbreviated, time: .shortened)) – \(last.formatted(date: .abbreviated, time: .shortened)) (camera clock)")
            }
            Text("About \(minutes) min or more over Wi-Fi.").foregroundStyle(.secondary)
        }
    }
}
