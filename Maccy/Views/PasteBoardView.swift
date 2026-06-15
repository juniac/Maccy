import SwiftUI

struct PasteBoardView: View {
  @State private var pasteBoardPopup = AppState.shared.pasteBoardPopup

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
    .environment(pasteBoardPopup)
    .frame(minHeight: PasteBoardPopup.minimumHeight, maxHeight: PasteBoardPopup.maximumHeight)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(NSLocalizedString(
        "paste_board_title",
        tableName: "Localizable",
        value: "Paste Board",
        comment: ""
      ))
        .font(.headline)
        .lineLimit(1)

      Spacer()

      Text("\(pasteBoardPopup.queue.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.leading, 44)
    .padding(.trailing, 12)
    .frame(height: PasteBoardPopup.fixedHeaderHeight)
  }

  @ViewBuilder
  private var content: some View {
    if pasteBoardPopup.queue.isEmpty {
      Text(NSLocalizedString(
        "paste_board_empty",
        tableName: "Localizable",
        value: "Empty",
        comment: ""
      ))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(pasteBoardPopup.queue.enumerated()), id: \.element.id) { index, item in
            PasteBoardItemView(item: item, index: index)
            if index != pasteBoardPopup.queue.count - 1 {
              Divider()
                .padding(.leading, 10)
            }
          }
        }
        .readHeight(pasteBoardPopup, into: \.contentHeight)
      }
      .frame(maxHeight: PasteBoardPopup.maximumHeight - PasteBoardPopup.fixedHeaderHeight)
      .onChange(of: pasteBoardPopup.contentHeight) {
        pasteBoardPopup.resizeForContentHeight()
      }
    }
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
    HStack(alignment: .top, spacing: 8) {
      Text("\(index + 1)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(width: 18, alignment: .topTrailing)

      if let thumbnailImage = item.thumbnailImage {
        Image(nsImage: thumbnailImage)
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
          .clipShape(RoundedRectangle(cornerRadius: 3))
      }

      Text(verbatim: title)
        .lineLimit(1...3)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 0)
    }
    .padding(.horizontal, PasteBoardPopup.rowHorizontalPadding)
    .padding(.vertical, PasteBoardPopup.rowVerticalPadding)
    .onAppear {
      item.ensureThumbnailImage()
    }
  }
}

#Preview {
  PasteBoardView()
    .environment(\.locale, .init(identifier: "en"))
}
