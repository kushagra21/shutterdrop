import SwiftUI

/// First-run guide to the camera modes Shutterdrop uses.
struct GuideView: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Setting up your A7 III").font(.title2.bold())

            section(
                "1. One-time pairing (USB)",
                icon: "cable.connector",
                """
                Send to Computer only works with a computer registered on the camera. Set \
                MENU → Setup → USB Connection → Mass Storage, plug the camera in, eject its \
                disk, then choose Camera → Pair Camera over USB (or Settings).
                """
            )
            section(
                "2. While shooting: live previews",
                icon: "dot.radiowaves.left.and.right",
                """
                On the camera choose MENU → Network → Ctrl w/ Smartphone. Join this Mac to the \
                camera's DIRECT-… Wi-Fi network, then click Start Live. Each shot appears about \
                a second later as a 1616×1080 preview. The Mac has no internet on that network.
                """
            )
            section(
                "3. Afterwards: full-size files",
                icon: "square.and.arrow.down",
                """
                Put the Mac back on your home Wi-Fi, click Import Full-Size and choose \
                MENU → Network → Send to Computer on the camera. The JPEG/ARW originals are \
                copied and paired with their previews.
                """
            )
            Text("macOS asks to allow Local Network access the first time. Allow it, or the camera can't be found.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Get Started", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func section(_ title: String, icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 30).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
