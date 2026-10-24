import AppKit
import ShutterdropCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Photo folder") {
                LibraryFolderControls()
            }
            Section("Camera pairing") {
                PairingControls()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

/// One-time USB pairing, needed before Send to Computer works.
struct PairingControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set the camera to MENU → Setup → USB Connection → Mass Storage, plug it in and eject its disk in Finder. Then pair; macOS asks for an administrator password.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Pair Camera over USB…") { model.pairCamera() }
                    .disabled(model.pairState == .pairing)
                switch model.pairState {
                case .idle: EmptyView()
                case .pairing: ProgressView().controlSize(.small)
                case .paired: Label("Paired. Unplug the camera and set USB Connection back.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case let .failed(message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        }
    }
}

/// The current photo folder, with Show in Finder and Change….
struct LibraryFolderControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.library.root.path, systemImage: "folder")
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .help(model.library.root.path)
            HStack {
                Button("Show in Finder") { model.revealInFinder([model.library.root]) }
                Button("Change…") { model.changeLibraryFolder() }
                    .disabled(!model.canChangeLibrary)
                if model.isMovingLibrary {
                    ProgressView().controlSize(.small)
                    Text("Moving photos…").foregroundStyle(.secondary)
                } else if !model.canChangeLibrary {
                    Text("Stop live previews and imports to change it.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}
