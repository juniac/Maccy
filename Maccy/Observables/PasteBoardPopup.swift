//
//  PasteBoardPopup.swift
//  Maccy
//
//  Created by garlic on 6/15/26.
//  Copyright © 2026 p0deje. All rights reserved.
//

import AppKit
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class PasteBoardPopup {
  static let minimumHeight: CGFloat = 150
  static let maximumHeight: CGFloat = 500
  static let fixedHeaderHeight: CGFloat = 38
  static let separatorHeight: CGFloat = 1
  static let rowHorizontalPadding: CGFloat = 10
  static let rowVerticalPadding: CGFloat = 8

  var queue: [HistoryItemDecorator] = []
  var contentHeight: CGFloat = 0

  private var eventsMonitor: Any?
  private var isOpening = false

  init() {
    KeyboardShortcuts.onKeyDown(for: .pasteBoard, action: handleFirstKeyDown)
    initEventsMonitor()
  }

  deinit {
    deinitEventsMonitor()
  }

  private func initEventsMonitor() {
    guard eventsMonitor == nil else { return }

    eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: handleEvent
    )
  }

  private func deinitEventsMonitor() {
    guard let eventsMonitor else { return }

    NSEvent.removeMonitor(eventsMonitor)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    MainActor.assumeIsolated {
      resetQueue()
      PasteBoard.shared.start()
    }
    AppState.shared.appDelegate?.pasteBoardPanel.open(height: height, at: popupPosition)
    MainActor.assumeIsolated {
      resizeForContentHeight()
    }
  }

  func reset() {
    MainActor.assumeIsolated {
      PasteBoard.shared.stop()
      resetQueue()
    }
    isOpening = false
    KeyboardShortcuts.enable(.pasteBoard)
  }

  func close() {
    AppState.shared.appDelegate?.pasteBoardPanel.close() // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.pasteBoardPanel.isPresented != true
  }

  private func handleFirstKeyDown() {
    if isClosed() {
      open(height: Self.minimumHeight)
      isOpening = true
      return
    }

    // Maccy was not opened via shortcut. We assume toggle mode and close it
    close()
  }

  @MainActor
  private func resetQueue() {
    queue.removeAll()
    contentHeight = 0
  }

  @MainActor
  func addCopiedItem(_ item: HistoryItem) {
    addCopiedItem(HistoryItemDecorator(snapshot(item)))
  }

  @MainActor
  private func addCopiedItem(_ item: HistoryItemDecorator) {
    guard PasteBoard.shared.isRunning,
          !hasQueuedEquivalent(item)
    else {
      return
    }

    queue.append(item)
  }

  private func snapshot(_ item: HistoryItem) -> HistoryItem {
    let copiedContents = item.contents.map {
      HistoryItemContent(type: $0.type, value: $0.value)
    }
    let copiedItem = HistoryItem(contents: copiedContents)
    copiedItem.application = item.application
    copiedItem.firstCopiedAt = item.firstCopiedAt
    copiedItem.lastCopiedAt = item.lastCopiedAt
    copiedItem.numberOfCopies = item.numberOfCopies
    copiedItem.title = item.title
    return copiedItem
  }

  @MainActor
  func removeQueuedItem(_ item: HistoryItemDecorator) {
    if let index = queue.firstIndex(of: item) {
      queue.remove(at: index)
    }

    if queue.isEmpty {
      contentHeight = 0
    }

    resizeForContentHeight()
  }

  private func hasQueuedEquivalent(_ item: HistoryItemDecorator) -> Bool {
    return queue.contains {
      $0.item == item.item ||
        $0.item.supersedes(item.item) ||
        item.item.supersedes($0.item)
    }
  }

  @MainActor
  func resizeForContentHeight() {
    let targetHeight = min(
      Self.maximumHeight,
      max(Self.minimumHeight, Self.fixedHeaderHeight + Self.separatorHeight + contentHeight)
    )
    AppState.shared.appDelegate?.pasteBoardPanel.verticallyResize(to: targetHeight)
  }

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .keyDown:
      return handleKeyDown(event)
    case .flagsChanged:
      return handleFlagsChanged(event)
    default:
      return event
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if matchesShortcut(.popup, event: event) {
      switchToPopup()
      return nil
    }

    if !isClosed(), matchesShortcut(.pasteBoard, event: event) {
      if isOpening {
        isOpening = false
        return nil
      }
      close()
      return nil
    }

    return event
  }

  private func switchToPopup() {
    close()
    AppState.shared.popup.open(height: AppState.shared.popup.height)
    KeyboardShortcuts.disable(.popup)
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    if isOpening, allModifiersReleased(event) {
      isOpening = false
    }

    return event
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    return event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
  }

  private func matchesShortcut(_ name: KeyboardShortcuts.Name, event: NSEvent) -> Bool {
    guard let shortcut = name.shortcut else {
      return false
    }

    return shortcut.key?.rawValue == Int(event.keyCode) &&
      event.modifierFlags.intersection(.deviceIndependentFlagsMask) ==
      shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
  }
}
