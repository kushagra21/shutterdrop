import AppKit
import Observation
import ShutterdropCore
import UserNotifications

/// Everything the window shows: the library, live mode and import.
@MainActor @Observable
final class AppModel {
    enum LiveState: Equatable {
        case off
        /// Not reachable yet; the message says what to do.
        case searching(String)
        case ready
        case receiving
    }

    enum ImportState: Equatable {
        case idle
        case waiting
        case connecting(String)
        case reading
        case confirm([PendingFile])
        case copying(index: Int, count: Int, name: String)
        case done(Int)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .idle, .done, .failed: false
            default: true
            }
        }
    }

    enum ImportRange: String, CaseIterable, Identifiable {
        case today, lastWeek, everything

        var id: Self { self }
        var title: String {
            switch self {
            case .today: "Today"
            case .lastWeek: "Last 7 days"
            case .everything: "Everything on the card"
            }
        }

        /// Cutoff by the camera's clock.
        func since(_ now: Date = Date()) -> Date? {
            let today = Calendar.current.startOfDay(for: now)
            return switch self {
            case .today: today
            case .lastWeek: Calendar.current.date(byAdding: .day, value: -6, to: today)
            case .everything: nil
            }
        }
    }

    static let libraryKey = "libraryRoot"
    static let importJPEGKey = "importJPEG"
    static let importRAWKey = "importRAW"
    /// How long to wait for the camera to announce Send to Computer.
    static let importWait: Double = 180

    private(set) var library: PhotoLibrary
    private(set) var days: [URL] = []
    var selectedDay: URL? { didSet { reloadShots() } }
    private(set) var shots: [Shot] = []
    var selectedShotID: Shot.ID?

    private(set) var live: LiveState = .off
    private(set) var lastProblem: String?
    /// Shots received while the app was in the background; shown on the Dock icon.
    private(set) var unseenShots = 0 { didSet { updateDockBadge() } }

    private(set) var importState: ImportState = .idle
    var importRange: ImportRange = .today
    var showingImport = false

    private var liveTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var confirmation: CheckedContinuation<Bool, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.libraryKey)
        library = PhotoLibrary(root: saved.map { URL(filePath: $0) } ?? PhotoLibrary.defaultRoot)
        reloadDays()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.unseenShots = 0 }
        }
    }

    var selectedShot: Shot? { shots.first { $0.id == selectedShotID } ?? shots.first }

    // MARK: - Library

    func setLibraryRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.libraryKey)
        library = PhotoLibrary(root: url)
        selectedDay = nil
        reloadDays()
    }

    func reloadDays() {
        days = library.days()
        if selectedDay == nil || !days.contains(selectedDay!) {
            selectedDay = days.first
        } else {
            reloadShots()
        }
    }

    func reloadShots() {
        shots = selectedDay.map(library.shots(inDay:)) ?? []
        if let selectedShotID, !shots.contains(where: { $0.id == selectedShotID }) {
            self.selectedShotID = nil
        }
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: - Live

    var isLive: Bool { live != .off }

    func startLive() {
        guard liveTask == nil else { return }
        live = .searching("On the camera choose Network → Ctrl w/ Smartphone, then join this Mac to its DIRECT-… Wi-Fi network.")
        lastProblem = nil
        let library = library
        liveTask = Task {
            while !Task.isCancelled {
                let camera = await RemoteCamera.discover()
                do {
                    try await LiveSession(camera: camera, library: library).run { update in
                        Task { @MainActor in self.apply(update) }
                    }
                } catch {
                    guard !Task.isCancelled else { break }
                    live = .searching("Camera not reachable yet. Is the Mac on the camera's DIRECT-… Wi-Fi? Retrying…")
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        live = .off
    }

    private func apply(_ update: LiveSession.Update) {
        guard isLive else { return }
        switch update {
        case .connected:
            live = .ready
        case let .status(status):
            live = status == "StillCapturing" ? .receiving : .ready
        case let .saved(photo):
            live = .ready
            if !NSApp.isActive { unseenShots += 1 }
            let day = library.dayFolder(photo.captured)
            days = library.days()
            if selectedDay != day { selectedDay = day } else { reloadShots() }
            selectedShotID = shots.first { $0.preview?.url.lastPathComponent == photo.url.lastPathComponent }?.id
        case let .problem(problem):
            lastProblem = problem
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = unseenShots > 0 ? "\(unseenShots)" : nil
    }

    // MARK: - Import

    func startImport() {
        guard importTask == nil else { return }
        importState = .waiting
        let defaults = UserDefaults.standard
        var formats: Set<UInt16> = []
        if defaults.object(forKey: Self.importJPEGKey) as? Bool ?? true { formats.insert(0x3801) }
        if defaults.object(forKey: Self.importRAWKey) as? Bool ?? true { formats.insert(0xB101) }
        let importer = CardImporter(library: library, formats: formats.isEmpty ? CardImporter.defaultFormats : formats, since: importRange.since())

        importTask = Task {
            defer { importTask = nil }
            do {
                guard let host = try await CardImporter.waitForCamera(seconds: Self.importWait) else {
                    importState = .failed("The camera didn't show up. Is Send to Computer running, with the camera on the same Wi-Fi as this Mac?")
                    return
                }
                importState = .connecting(host)
                let saved = try await importer.run(
                    host: host,
                    guid: try ClientIdentity.guid(),
                    name: ClientIdentity.name,
                    confirm: { files in await self.askToConfirm(files) }
                ) { update in
                    Task { @MainActor in self.apply(update) }
                }
                importState = .done(saved.count)
                reloadDays()
                notify("Import finished", "\(saved.count) full-size file(s) copied from the camera.")
            } catch is CancellationError {
                importState = .idle
            } catch {
                importState = .failed(String(describing: error))
            }
        }
    }

    /// Stops waiting, or stops after the file being copied.
    func cancelImport() {
        confirmation?.resume(returning: false)
        confirmation = nil
        importTask?.cancel()
    }

    func confirmImport(_ go: Bool) {
        confirmation?.resume(returning: go)
        confirmation = nil
    }

    func finishImportSheet() {
        if !importState.isActive { importState = .idle }
        showingImport = false
    }

    private func askToConfirm(_ files: [PendingFile]) async -> Bool {
        importState = .confirm(files)
        return await withCheckedContinuation { confirmation = $0 }
    }

    private func apply(_ update: CardImporter.Update) {
        guard importState.isActive else { return }
        switch update {
        case .connected:
            importState = .reading
        case .found:
            break  // the confirmation step shows the list
        case let .saved(photo, index, count):
            importState = .copying(index: index, count: count, name: photo.url.lastPathComponent)
            if library.dayFolder(photo.captured) == selectedDay { reloadShots() }
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard !NSApp.isActive else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
