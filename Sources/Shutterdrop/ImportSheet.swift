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
        .frame(width: choosing ? 640 : 480, height: choosing ? 620 : 400)
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
            ImportChooser(files: files)
        case let .copying(done, count, current):
            ImportSteps(state: model.importState)
            ProgressView(value: Double(done), total: Double(count)) {
                Text("Copied \(done) of \(count)")
            } currentValueLabel: {
                if let current {
                    Text("Copying \(current) (\(done + 1) of \(count))…")
                }
            }
            Text("Keep the camera on and near the router. Cancel closes this right away; the file being copied finishes in the background, and the next import carries on from there.")
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
            Button("Cancel", role: .cancel) { model.cancelImport() }
            let count = model.importChosenCount
            Button(count == 0 ? "Import" : "Import \(count) File\(count == 1 ? "" : "s")") {
                model.confirmImport(true)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(count == 0)
        case .done:
            Button("Done") { model.finishImportSheet() }.keyboardShortcut(.defaultAction)
        case .failed:
            Button("Close") { model.finishImportSheet() }
            Button("Try Again") { model.startImport() }.keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { model.cancelImport() }
        }
    }

    private var choosing: Bool {
        if case .confirm = model.importState { return true }
        return false
    }
}

/// The import steps with a tick for each one done and a spinner on the current one.
struct ImportSteps: View {
    let state: AppModel.ImportState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(1, "Waiting for the camera",
                detail: "Mac on home Wi-Fi; on the camera choose MENU → Network → Send to Computer.")
            if state.step == 1 {
                NetworkHint().padding(.leading, 28)
            }
            row(2, connectingTitle, detail: connectingDetail)
            row(3, readingTitle, detail: state.step == 3 ? "The camera answers one file at a time; this takes a while over Wi-Fi." : nil)
            if case let .reading(done, total) = state, total > 0 {
                ProgressView(value: Double(done), total: Double(total)).padding(.leading, 28)
            }
            row(4, state.step == 4 ? "Choose what to copy: your turn" : "Choose what to copy", detail: nil, waitsForUser: true)
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

    /// `waitsForUser`: the current step is a question, so no spinner.
    @ViewBuilder private func row(_ step: Int, _ title: String, detail: String?, waitsForUser: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if state.step > step {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if state.step == step, waitsForUser {
                    Image(systemName: "hand.point.right.fill").foregroundStyle(.tint)
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

/// Which network the Mac is on, for hints while waiting for the camera.
enum MacNetwork: Equatable {
    case offline
    /// Still joined to the camera's own DIRECT-… Wi-Fi (used for live previews).
    case cameraWiFi
    case connected(String)

    /// The A7 III's Wi-Fi Direct network hands out 192.168.122.x addresses.
    static func current() -> MacNetwork {
        var addresses: [String] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return .offline }
        defer { freeifaddrs(list) }
        var entry = list
        while let current = entry {
            defer { entry = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard let address = current.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        // Ignore link-local addresses: they're there even without a real network.
        let usable = addresses.filter { !$0.hasPrefix("169.254.") }
        if usable.contains(where: { $0.hasPrefix("192.168.122.") }) { return .cameraWiFi }
        return usable.first.map(MacNetwork.connected) ?? .offline
    }
}

/// Live network status under the "Waiting for the camera" step.
struct NetworkHint: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            switch MacNetwork.current() {
            case .offline:
                Label("This Mac has no network yet. Join your home Wi-Fi.", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            case .cameraWiFi:
                Label("This Mac is still on the camera's DIRECT-… Wi-Fi. Switch to your home Wi-Fi.", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            case let .connected(address):
                Label("This Mac is on the network (\(address)).", systemImage: "wifi")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// Pick which new photos to copy, and whether RAW, JPEG or both.
/// JPEG and ARW of one shot share a row.
struct ImportChooser: View {
    @Environment(AppModel.self) private var model
    let files: [PendingFile]

    /// One shot: files sharing a base name (DSC04662.JPG + DSC04662.ARW).
    struct Row: Identifiable {
        let id: String
        let files: [PendingFile]
        var captured: Date? { files.compactMap(\.captured).min() }
        var kinds: [String] { files.map { ($0.name as NSString).pathExtension.uppercased() }.sorted() }
        /// The camera keeps a thumbnail for each file; a JPEG's is the safest bet.
        var thumbnailFile: PendingFile { files.first { $0.name.uppercased().hasSuffix(".JPG") } ?? files[0] }
    }

    private var rows: [Row] {
        Dictionary(grouping: files, by: AppModel.shotName)
            .map { Row(id: $0.key, files: $0.value.sorted { $0.name < $1.name }) }
            .sorted { ($0.captured ?? .distantPast, $0.id) > ($1.captured ?? .distantPast, $1.id) }
    }

    var body: some View {
        @Bindable var model = model
        let chosen = model.chosenFiles(files)
        let bytes = chosen.reduce(UInt64(0)) { $0 + $1.size }
        // Measured on the A7 III: ~1.2 MB/s at first, slower on long imports.
        let minutes = max(1, Int((Double(bytes) / 1_000_000 / 60).rounded(.up)))
        let rows = rows
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Choose what to copy", systemImage: "hand.point.right.fill").font(.headline)
                Spacer()
                Button("Select All") { model.importSelection = Set(rows.map(\.id)) }
                Button("Select None") { model.importSelection = [] }
            }
            Picker("Download", selection: $model.importFormat) {
                ForEach(AppModel.FormatChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Text(model.importSelection.isEmpty
                 ? "\(rows.count) new photo(s) on the camera. Tick the ones to copy."
                 : "\(model.importSelection.count) of \(rows.count) photo(s) · \(chosen.count) file(s), \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) · about \(minutes) min over Wi-Fi")
                .foregroundStyle(.secondary)
            List(rows) { row in
                ImportChooserRow(row: row)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
        }
    }
}

struct ImportChooserRow: View {
    @Environment(AppModel.self) private var model
    let row: ImportChooser.Row
    @State private var thumbnail: NSImage?

    private var isOn: Binding<Bool> {
        Binding {
            model.importSelection.contains(row.id)
        } set: { on in
            if on { model.importSelection.insert(row.id) } else { model.importSelection.remove(row.id) }
        }
    }

    /// The files of this photo the current RAW/JPEG choice would download.
    private var downloads: [PendingFile] { row.files.filter { model.importFormat.includes($0.name) } }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: isOn).labelsHidden()
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 72, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.id).font(.body.monospacedDigit())
                HStack(spacing: 4) {
                    // Formats that will download are solid; skipped ones faded.
                    ForEach(row.kinds, id: \.self) { kind in
                        let included = downloads.contains { ($0.name as NSString).pathExtension.uppercased() == kind }
                        Text(kind).font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(included ? Color.accentColor.opacity(0.25) : Color.clear, in: Capsule())
                            .foregroundStyle(included ? .primary : .tertiary)
                    }
                    if downloads.isEmpty, isOn.wrappedValue {
                        Text("no \(model.importFormat == .raw ? "RAW" : "JPEG") for this photo").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let captured = row.captured {
                    Text(captured.formatted(date: .abbreviated, time: .shortened))
                }
                Text(ByteCountFormatter.string(fromByteCount: Int64(downloads.reduce(0) { $0 + $1.size }), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(isOn.wrappedValue ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
        .task(id: row.id) { thumbnail = await model.thumbnail(for: row.thumbnailFile) }
    }
}
