import SwiftUI
import AppKit

/// Mostra un'immagine che si trova sul telefono. Il caricamento parte quando la vista
/// compare ed è annullato se esce dallo schermo, così scorrendo si scaricano solo le
/// anteprime davvero visibili.
struct RemoteImageView: View {
    let serial: String
    let item: RemoteItem
    let maxPixel: Int
    var urgent = false
    var contentMode: ContentMode = .fit
    var showsPlaceholder = true

    @State private var image: NSImage?
    @State private var failed = false

    private var taskKey: String {
        "\(serial)|\(item.path)|\(item.size)|\(item.modified)|\(maxPixel)"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if showsPlaceholder {
                if failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: taskKey) {
            image = nil
            failed = false
            let result = await RemoteImageLoader.shared.image(
                serial: serial, item: item, maxPixel: maxPixel, urgent: urgent)
            if Task.isCancelled { return }
            if let result {
                image = result
            } else {
                failed = true
            }
        }
    }
}
