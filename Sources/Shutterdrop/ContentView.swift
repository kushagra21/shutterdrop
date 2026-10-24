import ShutterdropCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            DayList()
                .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            ShotGrid()
                .navigationSplitViewColumnWidth(min: 300, ideal: 420)
        } detail: {
            if let shot = model.selectedShot {
                ShotDetail(shot: shot)
            } else {
                ContentUnavailableView(
                    "No photos yet",
                    systemImage: "camera",
                    description: Text("Start Live Previews and take a photo, or import full-size files from the camera.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { LiveStatus() }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.isLive ? model.stopLive() : model.startLive()
                } label: {
                    Label(model.isLive ? "Stop Live" : "Start Live", systemImage: model.isLive ? "stop.circle" : "dot.radiowaves.left.and.right")
                }
                .help("Live previews from the camera's Ctrl w/ Smartphone mode")
                Button {
                    model.showingImport = true
                } label: {
                    Label("Import Full-Size", systemImage: "square.and.arrow.down")
                }
                .help("Copy full-size files over the camera's Send to Computer mode")
                Button {
                    model.revealInFinder([model.selectedDay ?? model.library.root])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
        }
        .sheet(isPresented: $model.showingImport) { ImportSheet() }
    }
}

// MARK: - Live status

struct LiveStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .help(help)
        .padding(.horizontal, 6)
    }

    private var color: Color {
        switch model.live {
        case .off: .gray
        case .searching: .orange
        case .ready: .green
        case .receiving: .blue
        }
    }

    private var title: String {
        switch model.live {
        case .off: "Live off"
        case .searching: "Looking for camera…"
        case .ready: "Live: ready"
        case .receiving: "Live: receiving…"
        }
    }

    private var help: String {
        if case let .searching(message) = model.live { return message }
        return model.lastProblem ?? title
    }
}

// MARK: - Days

struct DayList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(model.days, id: \.self, selection: $model.selectedDay) { day in
            Label(Self.title(day), systemImage: "calendar")
        }
        .overlay {
            if model.days.isEmpty {
                Text("No photos in\n\(model.library.root.path)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
        }
    }

    static func title(_ day: URL) -> String {
        guard let date = PhotoLibrary.date(ofDay: day) else { return "Undated" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Grid

struct ShotGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(model.shots) { shot in
                    ShotCell(shot: shot, selected: shot.id == model.selectedShot?.id)
                        .onTapGesture { model.selectedShotID = shot.id }
                }
            }
            .padding(10)
        }
        .overlay {
            if model.shots.isEmpty, model.selectedDay != nil {
                Text("No photos on this day").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(model.selectedDay.map(DayList.title) ?? "Shutterdrop")
        .navigationSubtitle(model.shots.isEmpty ? "" : "\(model.shots.count) photo(s)")
    }
}

struct ShotCell: View {
    let shot: Shot
    let selected: Bool

    var body: some View {
        PhotoImage(url: shot.displayURL)
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomLeading) { badge.padding(4) }
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .overlay(alignment: .bottomTrailing) {
                if let captured = shot.captured {
                    Text(captured.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit()).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white).padding(4)
                }
            }
            .contentShape(Rectangle())
    }

    /// Whether the full-size file has arrived yet.
    @ViewBuilder private var badge: some View {
        let kinds = Set(shot.originals.map { $0.url.pathExtension.uppercased() })
        let label = kinds.isEmpty ? "Preview" : kinds.sorted().joined(separator: "+")
        Text(label)
            .font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1)
            .background(kinds.isEmpty ? Color.orange : Color.green, in: Capsule()).foregroundStyle(.white)
            .help(kinds.isEmpty ? "Live preview only. Import full-size files to get the original." : "Full-size file imported")
    }
}

// MARK: - Detail

struct ShotDetail: View {
    @Environment(AppModel.self) private var model
    let shot: Shot

    var body: some View {
        VStack(spacing: 0) {
            PhotoImage(url: shot.displayURL, maxPixels: 2400, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            Form {
                if let captured = shot.captured {
                    LabeledContent("Taken (camera clock)", value: captured.formatted(date: .abbreviated, time: .standard))
                }
                if let preview = shot.preview {
                    FileRow(title: "Live preview", photo: preview)
                }
                if shot.originals.isEmpty {
                    LabeledContent("Full size") {
                        Text("Not imported yet").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(shot.originals, id: \.url) { FileRow(title: "Full size", photo: $0) }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 230)
        }
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    let title: String
    let photo: Photo

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(photo.url.lastPathComponent).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            Text(size).foregroundStyle(.secondary).monospacedDigit()
            Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(photo.url) }
                .help("Open in the default app")
            Button("Show in Finder", systemImage: "folder") { model.revealInFinder([photo.url]) }
                .help("Show in Finder")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private var size: String {
        let bytes = (try? photo.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
