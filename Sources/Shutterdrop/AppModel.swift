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
        case connecting(host: String, attempt: Int)
        /// `total` is 0 until the camera has said how many files it has.
        case reading(done: Int, total: Int)
        case confirm([PendingFile])
        /// `done` files copied of `count`; `current` is the one being copied now.
        case copying(done: Int, count: Int, current: String?)
        case done(Int)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .idle, .done, .failed: false
            default: true
            }
        }

        /// Position in the import steps, for the sheet's checklist.
        var step: Int {
            switch self {
            case .idle: 0
            case .waiting: 1
            case .connecting: 2
            case .reading: 3
            case .confirm: 4
            case .copying, .done: 5
            case .failed: -1
            }
        }
    }

    /// When the current import started, for the elapsed-time counter.
    private(set) var importStartedAt: Date?

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

    enum PairState: Equatable {
        case idle, pairing, paired, failed(String)
    }
    private(set) var pairState: PairState = .idle

    private var liveTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var confirmation: CheckedContinuation<[PendingFile], Never>?
    /// Which files of each chosen photo to download.
    enum FormatChoice: String, CaseIterable, Identifiable {
        case both, raw, jpeg

        var id: Self { self }
        var title: String {
            switch self {
            case .both: "RAW + JPEG"
            case .raw: "RAW only"
            case .jpeg: "JPEG only"
            }
        }

        func includes(_ fileName: String) -> Bool {
            let kind = (fileName as NSString).pathExtension.uppercased()
            return switch self {
            case .both: true
            case .raw: kind == "ARW"
            case .jpeg: kind == "JPG" || kind == "JPEG"
            }
        }
    }

    static let importFormatKey = "importFormat"

    var importFormat: FormatChoice = FormatChoice(rawValue: UserDefaults.standard.string(forKey: "importFormat") ?? "") ?? .both {
        didSet { UserDefaults.standard.set(importFormat.rawValue, forKey: Self.importFormatKey) }
    }

    /// While choosing: ticked photos (by shot name, e.g. DSC04662) and camera thumbnails.
    var importSelection: Set<String> = []
    private(set) var importThumbnails: [PendingFile.ID: NSImage] = [:]
    private var thumbnailLoader: ThumbnailLoader?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.libraryKey)
        library = PhotoLibrary(root: saved.map { URL(filePath: $0) } ?? PhotoLibrary.defaultRoot)
        upgradeToShutterdropFolder()
        reloadDays()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.unseenShots = 0 }
        }
    }

    /// Shots selected in the grid (for deleting). `selectedShotID` is the one shown in detail.
    var selection: Set<Shot.ID> = []

    var selectedShot: Shot? { shots.first { $0.id == selectedShotID } ?? shots.first }
    var selectedShots: [Shot] { shots.filter { selection.contains($0.id) } }

    /// Click selects one; ⌘-click toggles; ⇧-click extends from the last click.
    func select(_ shot: Shot, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.remove(shot.id) == nil { selection.insert(shot.id) }
        } else if modifiers.contains(.shift),
                  let anchor = shots.firstIndex(where: { $0.id == selectedShotID }),
                  let target = shots.firstIndex(where: { $0.id == shot.id }) {
            selection.formUnion(shots[min(anchor, target)...max(anchor, target)].map(\.id))
        } else {
            selection = [shot.id]
        }
        selectedShotID = shot.id
    }

    func selectAllShots() {
        selection = Set(shots.map(\.id))
    }

    // MARK: - Adjusting dates

    var dateAdjustment: DateAdjustment?

    /// Opens Adjust Dates with `reference` (else the photo in the detail pane) as the photo to set.
    func beginAdjustDates(reference: Shot? = nil) {
        guard let day = selectedDay, let reference = reference ?? selectedShot, reference.captured != nil else { return }
        dateAdjustment = DateAdjustment(reference: reference, selected: shotsToTrash, day: day, dayShots: shots)
    }

    /// Opens Adjust Dates for a whole day, set from its newest photo.
    func beginAdjustDates(day: URL) {
        let dayShots = library.shots(inDay: day)
        guard let reference = dayShots.first(where: { $0.captured != nil }) else { return }
        dateAdjustment = DateAdjustment(reference: reference, selected: [], day: day, dayShots: dayShots)
    }

    func applyDateShift(_ shots: [Shot], by offset: TimeInterval, reference: Shot) {
        do {
            try library.shiftDates(of: shots, by: offset)
        } catch {
            showError("Couldn't adjust every photo", error)
        }
        // Follow the photos to their corrected day.
        let newDay = library.dayFolder(reference.captured.map { $0 + offset })
        days = library.days()
        selectedDay = days.contains(newDay) ? newDay : days.first
        selection = []
    }

    // MARK: - Deleting

    /// Moves the shots' previews and full-size files to the Trash, after asking.
    func trash(_ shots: [Shot]) {
        guard !shots.isEmpty else { return }
        let files = shots.flatMap { [$0.preview].compactMap { $0 } + $0.originals }
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let alert = NSAlert()
        alert.messageText = shots.count == 1 ? "Move this photo to the Trash?" : "Move \(shots.count) photos to the Trash?"
        alert.informativeText = "\(files.count) file(s), \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), including previews and full-size files, are moved to the Trash in Finder. Photos still on the camera's card can be imported again."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            for shot in shots { try library.trash(shot) }
        } catch {
            showError("Couldn't move everything to the Trash", error)
        }
        selection.subtract(shots.map(\.id))
        reloadDays()
    }

    /// What a delete acts on: the selection, or else the photo in the detail pane.
    var shotsToTrash: [Shot] {
        selectedShots.isEmpty ? [selectedShot].compactMap { $0 } : selectedShots
    }

    func trashSelected() {
        trash(shotsToTrash)
    }

    /// Moves a whole day folder to the Trash, after asking.
    func trashDay(_ day: URL) {
        let count = library.shots(inDay: day).count
        let alert = NSAlert()
        alert.messageText = "Move all photos from \(ContentView.dayTitle(day)) to the Trash?"
        alert.informativeText = "\(count) photo(s) in \(day.path) are moved to the Trash in Finder."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try library.trashDay(day)
        } catch {
            showError("Couldn't move the day to the Trash", error)
        }
        if selectedDay == day { selectedDay = nil }
        reloadDays()
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    // MARK: - Library

    /// False until the first-run folder step has been completed.
    var isLibraryConfigured: Bool { UserDefaults.standard.string(forKey: Self.libraryKey) != nil }

    /// Changing folders mid-transfer would split a session across two libraries.
    var canChangeLibrary: Bool { !isLive && !importState.isActive }

    func setLibraryRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.libraryKey)
        library = PhotoLibrary(root: url)
        selectedDay = nil
        reloadDays()
    }

    /// Libraries chosen before photos went into a `Shutterdrop` subfolder kept
    /// day folders directly in the chosen folder; move them into one.
    private func upgradeToShutterdropFolder() {
        guard isLibraryConfigured, library.root.lastPathComponent != PhotoLibrary.folderName else { return }
        let old = library
        let new = PhotoLibrary.root(in: old.root)
        do {
            let moved = try old.moveContents(to: new)
            setLibraryRoot(new)
            if moved > 0 {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Photos moved into a Shutterdrop folder"
                    alert.informativeText = "To keep \(old.root.lastPathComponent) tidy, Shutterdrop now saves into \(new.path). Your \(moved) existing file(s) were moved there."
                    alert.runModal()
                }
            }
        } catch {
            // Leave everything where it is; the app keeps using the old folder.
            DispatchQueue.main.async { self.showError("Couldn't move photos into a Shutterdrop folder", error) }
        }
    }

    /// Lets the user pick a folder, starting from `start`.
    func chooseFolder(startingAt start: URL, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.fileExists(atPath: start.path) ? start : start.deletingLastPathComponent()
        panel.prompt = prompt
        panel.message = "Shutterdrop creates a folder named \"Shutterdrop\" inside the folder you choose, with a folder per day."
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Choose a new library folder and offer to bring the existing photos along.
    func changeLibraryFolder() {
        guard canChangeLibrary, let url = chooseFolder(startingAt: library.root.deletingLastPathComponent(), prompt: "Use Folder") else { return }
        adoptLibraryFolder(PhotoLibrary.root(in: url))
    }

    /// Switches to the library at `url` (already a `Shutterdrop` folder),
    /// offering to move the photos already in the current one. Returns false
    /// if the user cancelled.
    @discardableResult
    func adoptLibraryFolder(_ url: URL) -> Bool {
        let (files, bytes) = library.contentsSummary()
        guard url.standardizedFileURL != library.root.standardizedFileURL, files > 0 else {
            setLibraryRoot(url)
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Move your existing photos?"
        alert.informativeText = """
            \(files) file(s), \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)), are in \(library.root.path).
            Move them to \(url.path)? If you don't, they stay where they are and the app shows only the new folder.
            """
        alert.addButton(withTitle: "Move Photos")
        alert.addButton(withTitle: "Don't Move")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            moveLibrary(to: url)
            return true
        case .alertSecondButtonReturn:
            setLibraryRoot(url)
            return true
        default:
            return false
        }
    }

    private(set) var isMovingLibrary = false

    private func moveLibrary(to url: URL) {
        isMovingLibrary = true
        let library = library
        Task {
            defer { isMovingLibrary = false }
            do {
                try await Self.move(library, to: url)
                setLibraryRoot(url)
            } catch {
                // Whatever moved is in the new folder; whatever didn't is still in the old one.
                let alert = NSAlert()
                alert.messageText = "Couldn't move all photos"
                alert.informativeText = "\(error.localizedDescription)\n\nThe app still uses \(library.root.path)."
                alert.runModal()
                reloadDays()
            }
        }
    }

    @concurrent
    private static func move(_ library: PhotoLibrary, to url: URL) async throws {
        try library.moveContents(to: url)
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
        selection.formIntersection(shots.map(\.id))
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
            selection = Set([selectedShotID].compactMap { $0 })
        case let .problem(problem):
            lastProblem = problem
        }
    }

    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = unseenShots > 0 ? "\(unseenShots)" : nil
    }

    // MARK: - Import

    /// Bumped by every start and cancel, so a cancelled import still winding
    /// down in the background can't touch the state of a newer one.
    private var importGeneration = 0

    func startImport() {
        importGeneration += 1
        let generation = importGeneration
        importState = .waiting
        importStartedAt = Date()
        // Both formats are listed; the chooser picks RAW, JPEG or both.
        let importer = CardImporter(library: library, since: importRange.since())

        importTask = Task {
            do {
                guard let host = try await CardImporter.waitForCamera(seconds: Self.importWait) else {
                    setImportState(.failed("The camera didn't show up. Is Send to Computer running, with the camera on the same Wi-Fi as this Mac?"), generation: generation)
                    return
                }
                setImportState(.connecting(host: host, attempt: 1), generation: generation)
                let saved = try await importer.run(
                    host: host,
                    guid: try ClientIdentity.guid(),
                    name: ClientIdentity.name,
                    choose: { files, loader in await self.askToChoose(files, loader: loader, generation: generation) }
                ) { progress in
                    Task { @MainActor in self.apply(progress, generation: generation) }
                }
                reloadDays()
                guard !Task.isCancelled else { return }
                setImportState(.done(saved.count), generation: generation)
                notify("Import finished", "\(saved.count) full-size file(s) copied from the camera.")
            } catch {
                guard !Task.isCancelled else { return }
                setImportState(.failed(String(describing: error)), generation: generation)
            }
        }
    }

    /// Only the current import may change what the sheet shows.
    private func setImportState(_ state: ImportState, generation: Int) {
        if generation == importGeneration { importState = state }
    }

    /// Closes the sheet at once. In the background the import stops waiting,
    /// or stops after the file being copied, and signs off with the camera.
    func cancelImport() {
        importGeneration += 1
        endChoosing(with: [])
        importTask?.cancel()
        importTask = nil
        importState = .idle
        showingImport = false
    }

    /// Copies the ticked files (`go`), or none.
    func confirmImport(_ go: Bool) {
        guard case let .confirm(files) = importState else { return }
        let chosen = go ? chosenFiles(files) : []
        // Show copying at once: the first file takes a while to arrive.
        if !chosen.isEmpty {
            importState = .copying(done: 0, count: chosen.count, current: chosen.first?.name)
        }
        endChoosing(with: chosen)
    }

    /// The files to download: of the ticked photos, the formats picked.
    func chosenFiles(_ files: [PendingFile]) -> [PendingFile] {
        files.filter { importSelection.contains(Self.shotName($0)) && importFormat.includes($0.name) }
    }

    /// How many files the chooser would download right now.
    var importChosenCount: Int {
        if case let .confirm(files) = importState { return chosenFiles(files).count }
        return 0
    }

    /// DSC04662.ARW and DSC04662.JPG are one photo, "DSC04662".
    static func shotName(_ file: PendingFile) -> String {
        (file.name as NSString).deletingPathExtension
    }

    private func endChoosing(with chosen: [PendingFile]) {
        confirmation?.resume(returning: chosen)
        confirmation = nil
        thumbnailLoader = nil
        importThumbnails = [:]
    }

    /// The camera's thumbnail for a file, fetched once while choosing.
    func thumbnail(for file: PendingFile) async -> NSImage? {
        if let cached = importThumbnails[file.id] { return cached }
        guard let loader = thumbnailLoader, let data = await loader(file), let image = NSImage(data: data) else { return nil }
        importThumbnails[file.id] = image
        return image
    }

    func finishImportSheet() {
        if !importState.isActive { importState = .idle }
        showingImport = false
    }

    private func askToChoose(_ files: [PendingFile], loader: @escaping ThumbnailLoader, generation: Int) async -> [PendingFile] {
        guard generation == importGeneration, !Task.isCancelled else { return [] }
        // Everything in the chosen date range starts ticked.
        importSelection = Set(files.map(Self.shotName))
        thumbnailLoader = loader
        importState = .confirm(files)
        return await withCheckedContinuation { confirmation = $0 }
    }

    private func apply(_ update: CardImporter.Update, generation: Int) {
        guard generation == importGeneration, importState.isActive else { return }
        switch update {
        case let .retrying(attempt):
            if case let .connecting(host, _) = importState { importState = .connecting(host: host, attempt: attempt) }
        case .connected:
            importState = .reading(done: 0, total: 0)
        case let .reading(done, total):
            importState = .reading(done: done, total: total)
        case .found:
            break  // the confirmation step shows the list
        case let .copying(name, index, count):
            importState = .copying(done: index - 1, count: count, current: name)
        case let .saved(photo, index, count):
            importState = .copying(done: index, count: count, current: nil)
            if library.dayFolder(photo.captured) == selectedDay { reloadShots() }
        }
    }

    // MARK: - Pairing

    /// Runs `sdprobe pair` (bundled next to the app) as root: macOS asks for an
    /// administrator password, which taking the camera from the storage driver needs.
    /// Checks the camera first and reports the outcome in an alert.
    func pairCamera() {
        guard pairState != .pairing else { return }
        guard let tool = Bundle.main.url(forAuxiliaryExecutable: "sdprobe") else {
            return finishPairing(.failed("sdprobe is missing from the app bundle; rebuild with scripts/build-app.sh."))
        }

        let camera = CameraPairing.connectedCamera()
        guard camera.found else {
            return finishPairing(.failed("No Sony camera found on USB. Connect it with a cable and turn it on."))
        }
        guard camera.massStorage else {
            return finishPairing(.failed("The camera is connected but not in Mass Storage mode. On the camera choose MENU → Setup → USB Connection → Mass Storage, then reconnect the cable."))
        }

        let confirm = NSAlert()
        confirm.messageText = "Pair the camera with this Mac?"
        confirm.informativeText = """
            The camera is connected in Mass Storage mode. If its disk is showing in Finder, eject it first (keep the cable in).

            macOS will ask for an administrator password. The camera's disk disappears briefly while pairing.
            """
        confirm.addButton(withTitle: "Pair")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        pairState = .pairing
        Task {
            do {
                let guid = ClientIdentity.hex(try ClientIdentity.guid())
                let (ok, output) = await Self.runAsAdministrator(tool, arguments: ["pair", "--guid", guid])
                finishPairing(ok ? .paired : .failed(Self.pairingFailure(output)), details: output)
            } catch {
                finishPairing(.failed(String(describing: error)))
            }
        }
    }

    private func finishPairing(_ state: PairState, details: String = "") {
        pairState = state
        let alert = NSAlert()
        switch state {
        case .paired:
            alert.messageText = "Camera paired"
            alert.informativeText = "Unplug the camera and set USB Connection back to what it was. Send to Computer will now connect to Shutterdrop."
        case let .failed(message):
            alert.alertStyle = .warning
            alert.messageText = message == "Cancelled." ? "Pairing cancelled" : "Pairing failed"
            alert.informativeText = message
            if !details.isEmpty, message != "Cancelled." {
                let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 120))
                text.string = details.replacingOccurrences(of: "\r", with: "\n")
                text.isEditable = false
                text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                let scroll = NSScrollView(frame: text.frame)
                scroll.documentView = text
                scroll.hasVerticalScroller = true
                alert.accessoryView = scroll
            }
        default:
            return
        }
        alert.runModal()
    }

    @concurrent
    private static func runAsAdministrator(_ tool: URL, arguments: [String]) async -> (ok: Bool, output: String) {
        // Paths and arguments go in as argv and are quoted by AppleScript itself.
        let script = """
            on run argv
                set command to quoted form of item 1 of argv
                repeat with argument in rest of argv
                    set command to command & " " & quoted form of argument
                end repeat
                do shell script command & " 2>&1" with administrator privileges
            end run
            """
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        // "with administrator privileges" runs commands outside the user's login
        // session, where opening the camera's USB interface fails (IOUSBHost
        // internal error). `launchctl asuser` brings it back into the session.
        let inSession = ["/bin/launchctl", "asuser", String(getuid()), tool.path]
        process.arguments = ["-e", script] + inSession + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (false, String(describing: error))
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus == 0, output)
    }

    /// The useful line from sdprobe's or osascript's output.
    private static func pairingFailure(_ output: String) -> String {
        if output.contains("-128") { return "Cancelled." }
        // AppleScript turns line breaks into carriage returns.
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let message = lines.last { $0.contains("sdprobe:") } ?? lines.last ?? output
        return message.replacingOccurrences(of: #"^.*sdprobe: "#, with: "", options: .regularExpression)
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
