import AppKit
import SwiftUI

@main
struct ShutterdropApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()
    @AppStorage("hasSeenGuide") private var hasSeenGuide = false
    @State private var firstRunSheet: FirstRunSheet?

    /// First run: choose the photo folder, then the camera guide.
    enum FirstRunSheet: Identifiable {
        case folder, guide
        var id: Self { self }
    }

    var body: some Scene {
        Window("Shutterdrop", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .sheet(item: $firstRunSheet) { sheet in
                    switch sheet {
                    case .folder:
                        FolderSetupView { firstRunSheet = hasSeenGuide ? nil : .guide }
                            .environment(model)
                            .interactiveDismissDisabled()
                    case .guide:
                        GuideView { firstRunSheet = nil; hasSeenGuide = true }
                    }
                }
                .onAppear {
                    if !model.isLibraryConfigured { firstRunSheet = .folder }
                    else if !hasSeenGuide { firstRunSheet = .guide }
                }
        }
        .commands {
            CommandGroup(replacing: .help) {
                Button("Camera Setup Guide") { firstRunSheet = .guide }
            }
            CommandGroup(after: .newItem) {
                Button("Change Photo Folder…") { model.changeLibraryFolder() }
                    .disabled(!model.canChangeLibrary)
                Button("Show Photo Folder in Finder") { model.revealInFinder([model.library.root]) }
            }
            CommandMenu("Camera") {
                Button(model.isLive ? "Stop Live Previews" : "Start Live Previews") {
                    model.isLive ? model.stopLive() : model.startLive()
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Import Full-Size Files…") { model.showingImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Pair Camera over USB…") { model.pairCamera() }
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also show in the Dock when run straight from `swift run`, outside the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let path = ProcessInfo.processInfo.environment["SHUTTERDROP_SNAPSHOT"] {
            snapshotWindow(to: URL(filePath: path))
        }
    }

    /// Debug aid: saves the main window as a PNG a few seconds after launch
    /// (an app can image its own window without Screen Recording permission).
    private func snapshotWindow(to url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.attachedSheet == nil && $0.contentView != nil })
                    ?? NSApp.windows.first(where: \.isVisible),
                  let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            if let sheet = window.attachedSheet, let sheetView = sheet.contentView?.superview,
               let sheetBitmap = sheetView.bitmapImageRepForCachingDisplay(in: sheetView.bounds) {
                sheetView.cacheDisplay(in: sheetView.bounds, to: sheetBitmap)
                try? sheetBitmap.representation(using: .png, properties: [:])?
                    .write(to: url.deletingPathExtension().appendingPathExtension("sheet.png"))
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
