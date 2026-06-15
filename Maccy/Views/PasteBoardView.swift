import SwiftUI

struct PasteBoardView: View {
  @State private var appState = AppState.shared
  @State private var pasteBoardPopup = AppState.shared.pasteBoardPopup
  @State private var scenePhase: ScenePhase = .background

  var pasteBoard: PasteBoard

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      VStack(spacing: 0) {
        header
        Divider()
        content
      }
    }
    .environment(appState)
    .environment(pasteBoardPopup)
    .environment(\.scenePhase, scenePhase)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
      updateScenePhase(for: $0, to: .active)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
      updateScenePhase(for: $0, to: .background)
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text(NSLocalizedString(
        "paste_board_title",
        tableName: "Localizable",
        value: "Paste Board",
        comment: ""
      ))
        .font(.headline)
        .lineLimit(1)

      Spacer()

      Text("\(pasteBoard.items.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.leading, 44)
    .padding(.trailing, 12)
    .frame(height: 38)
  }

  @ViewBuilder
  private var content: some View {
    if pasteBoard.items.isEmpty {
      Text("paste_board_empty", tableName: "Localizable")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(pasteBoard.items.enumerated()), id: \.element.id) { index, item in
            PasteBoardItemView(item: item, index: index)
            if index != pasteBoard.items.count - 1 {
              Divider()
                .padding(.leading, 10)
            }
          }
        }
        .padding(.vertical, 5)
      }
    }
  }

  private var windowIdentifier: NSUserInterfaceItemIdentifier? {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }

    return NSUserInterfaceItemIdentifier("\(bundleIdentifier).PasteBoard")
  }

  private func updateScenePhase(for notification: Notification, to newPhase: ScenePhase) {
    guard let window = notification.object as? NSWindow,
          let windowIdentifier,
          window.identifier == windowIdentifier
    else {
      return
    }

    scenePhase = newPhase
  }
}

private struct PasteBoardItemView: View {
  var item: HistoryItemDecorator
  var index: Int

  private var title: String {
    if item.title.isEmpty, item.hasImage {
      return NSLocalizedString("paste_board_image", tableName: "Localizable", comment: "")
    }

    return item.title
  }

  var body: some View {
    HStack(spacing: 8) {
      Text("\(index + 1)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(width: 18, alignment: .trailing)

      if let thumbnailImage = item.thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
          .clipShape(RoundedRectangle(cornerRadius: 3))
      }

      Text(verbatim: title)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 0)
    }
    .frame(height: 28)
    .padding(.horizontal, 10)
    .onAppear {
      item.ensureThumbnailImage()
    }
  }
}

#Preview {
  PasteBoardView(pasteBoard: PasteBoard.shared)
    .environment(\.locale, .init(identifier: "en"))
}
