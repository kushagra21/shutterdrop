import ShutterdropCore
import SwiftUI

/// First-run step: choose where photos are saved.
struct FolderSetupView: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void

    @State private var folder = PhotoLibrary.defaultRoot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where should Shutterdrop save photos?").font(.title2.bold())
            Text("Live previews and full-size files go into this folder, one subfolder per day. You can change it later from the sidebar or Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.lastPathComponent).font(.headline)
                    Text(LibraryFooter.displayPath(folder)).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Choose Another…") {
                    if let url = model.chooseFolder(startingAt: folder, prompt: "Choose") { folder = url }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Use This Folder") {
                    if model.adoptLibraryFolder(folder) { done() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { folder = model.library.root }
    }
}
