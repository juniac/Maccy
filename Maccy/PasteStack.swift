import AppKit
import Foundation
import KeyboardShortcuts
import Observation
import Sauce

@Observable
class PasteStack: Identifiable, Hashable {
  private static var listener: Any?

  static func initializeIfNeeded() {
    guard listener == nil else { return }
    Accessibility.check()

    var pasteDown = false
    listener = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .keyDown]) { event in
      switch event.type {
      case .keyDown:
        if event.keyCode == KeyChord.pasteKey.QWERTYKeyCode,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command]
        {
          pasteDown = true
        }
      case .keyUp:
        if pasteDown, event.keyCode == KeyChord.pasteKey.QWERTYKeyCode {
          pasteDown = false
          AppState.shared.history.handlePasteStack()
        }
      default:
        break
      }
    }
  }

  var id: UUID = .init()
  var items: [HistoryItemDecorator] = []
  var modifierFlags: NSEvent.ModifierFlags

  init(items: [HistoryItemDecorator], modifierFlags: NSEvent.ModifierFlags) {
    self.items = items
    self.modifierFlags = modifierFlags
  }

  static func == (lhs: PasteStack, rhs: PasteStack) -> Bool {
    return lhs.id == rhs.id
      && lhs.items == rhs.items
      && lhs.modifierFlags.rawValue == rhs.modifierFlags.rawValue
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(items)
    hasher.combine(modifierFlags.rawValue)
  }
}

@Observable
class PasteBoard {
  static let shared = PasteBoard()

  private static let forwardedPasteMarker: Int64 = 0x4d616363795042
  private static var copyMonitor: Any?
  private static var originalPasteDown = false
  private static var pasteEventTap: CFMachPort?
  private static var pasteEventTapSource: CFRunLoopSource?

  var isRunning = false
  var items: [HistoryItemDecorator] = []

  private var copyCheckTask: Task<Void, Never>?

  private init() {}

  @MainActor
  static func initializeIfNeeded() {
    Accessibility.check()
    initializeCopyMonitorIfNeeded()
    initializePasteEventTapIfNeeded()
  }

  private static func initializeCopyMonitorIfNeeded() {
    guard copyMonitor == nil else { return }
    var copyDown = false
    copyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .keyDown]) { event in
      switch event.type {
      case .keyDown:
        if isCopyShortcut(event) {
          copyDown = true
        }
      case .keyUp:
        if copyDown, isCopyKey(event) {
          copyDown = false
          Task { @MainActor in
            PasteBoard.shared.handleCopyShortcutCompleted()
          }
        }
      default:
        break
      }
    }
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

    guard event.getIntegerValueField(.eventSourceUserData) != forwardedPasteMarker else {
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
    items.removeAll()
    isRunning = true
    Self.setPasteEventTapEnabled(true)
    KeyboardShortcuts.disable(.popup)
  }

  @MainActor
  func stop() {
    copyCheckTask?.cancel()
    isRunning = false
    Self.originalPasteDown = false
    items.removeAll()
    Self.setPasteEventTapEnabled(false)
    KeyboardShortcuts.enable(.popup)
  }

  @MainActor
  func enqueue(_ item: HistoryItemDecorator) {
    guard isRunning, !item.item.fromMaccy else { return }

    items.append(item)
  }

  private static func isCopyShortcut(_ event: NSEvent) -> Bool {
    return isCopyKey(event) && normalizedModifierFlags(event) == [.command]
  }

  private static func isPasteShortcut(_ event: NSEvent) -> Bool {
    return isPasteKey(event) && normalizedModifierFlags(event) == [.command]
  }

  private static func isPasteShortcut(_ event: CGEvent) -> Bool {
    return isPasteKey(event) && normalizedModifierFlags(event) == [.maskCommand]
  }

  private static func isCopyKey(_ event: NSEvent) -> Bool {
    return key(from: event) == .c
  }

  private static func isPasteKey(_ event: NSEvent) -> Bool {
    return Int(event.keyCode) == KeyChord.pasteKey.QWERTYKeyCode
  }

  private static func isPasteKey(_ event: CGEvent) -> Bool {
    return Int(event.getIntegerValueField(.keyboardEventKeycode)) == KeyChord.pasteKey.QWERTYKeyCode
  }

  private static func key(from event: NSEvent) -> Key? {
    let modifiers = normalizedModifierFlags(event)
    if KeyboardLayout.current.commandSwitchesToQWERTY, modifiers.contains(.command) {
      return Key(QWERTYKeyCode: Int(event.keyCode))
    }

    return Sauce.shared.key(for: Int(event.keyCode))
  }

  private static func normalizedModifierFlags(_ event: NSEvent) -> NSEvent.ModifierFlags {
    return event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
  }

  private static func normalizedModifierFlags(_ event: CGEvent) -> CGEventFlags {
    return event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
  }

  private static func setPasteEventTapEnabled(_ enabled: Bool) {
    guard let pasteEventTap else { return }
    CGEvent.tapEnable(tap: pasteEventTap, enable: enabled)
  }

  @MainActor
  private func handleCopyShortcutCompleted() {
    guard isRunning else { return }

    copyCheckTask?.cancel()
    copyCheckTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }

      Clipboard.shared.checkForChangesInPasteboard()
    }
  }

  @discardableResult
  @MainActor
  func handlePasteShortcutKeyDown() -> Bool {
    guard isRunning, let item = items.first else { return false }
    let index = 0

//    AppState.shared.history.select(item)
//    Clipboard.shared.paste(eventSourceUserData: Self.forwardedPasteMarker)
//    removeItem(at: index)

    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled else { return }

      AppState.shared.history.delete(item)
    }

    return true
  }
}
