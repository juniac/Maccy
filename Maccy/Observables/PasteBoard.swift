import AppKit
import KeyboardShortcuts
import Observation

@Observable
class PasteBoard {
  static let shared = PasteBoard()

  private static var originalPasteDown = false
  private static var isForwardingPaste = false
  private static var pasteEventTap: CFMachPort?
  private static var pasteEventTapSource: CFRunLoopSource?

  var isRunning = false
  private var pendingPastedItem: HistoryItem?

  private init() {}

  @MainActor
  private static func initializeIfNeeded() {
    Accessibility.check()
    initializePasteEventTapIfNeeded()
  }

  private static func initializePasteEventTapIfNeeded() {
    guard pasteEventTap == nil else { return }

    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
      CGEventMask(1 << CGEventType.keyUp.rawValue)
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: pasteEventTapCallback,
      userInfo: nil
    ) else {
      return
    }

    pasteEventTap = eventTap
    pasteEventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let pasteEventTapSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), pasteEventTapSource, .commonModes)
    }
    CGEvent.tapEnable(tap: eventTap, enable: false)
  }

  private static let pasteEventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let pasteEventTap {
        CGEvent.tapEnable(tap: pasteEventTap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
      return Unmanaged.passUnretained(event)
    }

    if isForwardingPaste {
      if type == .keyUp, isPasteKey(event) {
        isForwardingPaste = false
      }
      return Unmanaged.passUnretained(event)
    }

    guard PasteBoard.shared.isRunning else {
      originalPasteDown = false
      return Unmanaged.passUnretained(event)
    }

    if type == .keyUp, originalPasteDown, isPasteKey(event) {
      originalPasteDown = false
      return nil
    }

    if type == .keyDown, isPasteShortcut(event) {
      guard !originalPasteDown else {
        return nil
      }

      originalPasteDown = true
      MainActor.assumeIsolated {
        PasteBoard.shared.handlePasteShortcutKeyDown()
      }
      return nil
    }

    return Unmanaged.passUnretained(event)
  }

  @MainActor
  func start() {
    Self.initializeIfNeeded()
    isRunning = true
    Self.setPasteEventTapEnabled(true)
    KeyboardShortcuts.disable(.popup)
  }

  @MainActor
  func stop() {
    isRunning = false
    pendingPastedItem = nil
    Self.originalPasteDown = false
    Self.isForwardingPaste = false
    Self.setPasteEventTapEnabled(false)
    KeyboardShortcuts.enable(.popup)
  }

  private static func isPasteShortcut(_ event: CGEvent) -> Bool {
    return isPasteKey(event) && normalizedModifierFlags(event) == [.maskCommand]
  }

  private static func isPasteKey(_ event: CGEvent) -> Bool {
    return Int(event.getIntegerValueField(.keyboardEventKeycode)) == KeyChord.pasteKey.QWERTYKeyCode
  }

  private static func normalizedModifierFlags(_ event: CGEvent) -> CGEventFlags {
    return event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
  }

  private static func setPasteEventTapEnabled(_ enabled: Bool) {
    guard let pasteEventTap else { return }
    CGEvent.tapEnable(tap: pasteEventTap, enable: enabled)
  }

  @MainActor
  private func handlePasteShortcutKeyDown() {
    guard isRunning, let item = AppState.shared.pasteBoardPopup.queue.first else { return }

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }

      prepareToPasteQueuedItem(item)
      AppState.shared.history.select(item)
      AppState.shared.pasteBoardPopup.removeQueuedItem(item)
    }
  }

  @MainActor
  func consumePendingPasteCopy(_ item: HistoryItem) -> Bool {
    guard isRunning, let pendingPastedItem else {
      return false
    }

    let shouldConsume = item.fromMaccy ||
      pendingPastedItem == item ||
      pendingPastedItem.supersedes(item) ||
      item.supersedes(pendingPastedItem)

    if shouldConsume {
      self.pendingPastedItem = nil
    }

    return shouldConsume
  }

  @MainActor
  private func prepareToPasteQueuedItem(_ item: HistoryItemDecorator) {
    Self.isForwardingPaste = true
    pendingPastedItem = item.item
  }
}
