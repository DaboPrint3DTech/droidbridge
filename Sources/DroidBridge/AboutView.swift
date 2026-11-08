import SwiftUI
import AppKit

struct AboutView: View {
    @State private var adbVersion = "…"

    var body: some View {
        VStack(spacing: 14) {
            // The app logo (AppIcon.icns, generated from Resources/AppIcon.png by build.sh)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)

            VStack(spacing: 4) {
                Text(AppInfo.name)
                    .font(.title.bold())
                Text("Version \(AppInfo.versionString)")
                    .foregroundStyle(.secondary)
            }

            Text(AppInfo.summary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                infoRow("Creator", AppInfo.creator)
                infoRow("Android Debug Bridge", adbVersion)
                infoRow("adb path", ADB.executablePath ?? "not found")
                infoRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            }

            Divider()

            VStack(spacing: 4) {
                Text(AppInfo.copyright)
                Text(AppInfo.disclaimer)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
        .padding(24)
        .frame(width: 400)
        .task { adbVersion = await AppInfo.adbVersion() }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
