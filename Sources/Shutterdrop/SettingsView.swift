import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppModel.importJPEGKey) private var importJPEG = true
    @AppStorage(AppModel.importRAWKey) private var importRAW = true

    var body: some View {
        Form {
            LabeledContent("Photo library") {
                HStack {
                    Text(model.library.root.path).truncationMode(.middle).lineLimit(1)
                    Button("Choose…", action: chooseFolder)
                }
            }
            Section("Import from the camera") {
                Toggle("JPEG files", isOn: $importJPEG)
                Toggle("RAW (ARW) files", isOn: $importRAW)
                if !importJPEG && !importRAW {
                    Text("With neither selected, both are imported.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.library.root
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url {
            model.setLibraryRoot(url)
        }
    }
}
