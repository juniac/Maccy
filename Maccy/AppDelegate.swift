import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  static let isTesting = CommandLine.arguments.contains("enable-testing")
  var panel: FloatingPanel<ContentView>!
  var pasteBoardPanel: FloatingPanel<PasteBoardView>!

  private let pasteBoardContentRectKey = "pasteBoardContentRect"
  private let pasteBoardPanelWidth: CGFloat = 360
  private var pasteBoardPanelSize: NSSize {
    NSSize(width: pasteBoardPanelWidth, height: PasteBoardPopup.minimumHeight)
  }
  private var pasteBoardPanelMaxSize: NSSize {
    NSSize(width: pasteBoardPanelWidth, height: PasteBoardPopup.maximumHeight)
  }
  private var defaultPasteBoardContentRect: NSRect {
    NSRect(origin: .zero, size: pasteBoardPanelSize)
  }
  private var savedPasteBoardContentRect: NSRect? {
    guard let contentRectString = UserDefaults.standard.string(forKey: pasteBoardContentRectKey) else {
      return nil
    }

    var contentRect = NSRectFromString(contentRectString)
    guard !contentRect.isEmpty else {
      return nil
    }

    contentRect.size.width = pasteBoardPanelWidth
    contentRect.size.height = min(
      PasteBoardPopup.maximumHeight,
      max(PasteBoardPopup.minimumHeight, contentRect.height)
    )
    return contentRect
  }

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  // Base accessibility label for the status item; kept separate from the optional
  // dynamic `title` (recent copy text) so VoiceOver always announces something
  // meaningful even when that preference is off or the app is disabled.
  private func updateStatusItemAccessibilityLabel() {
    let base = NSLocalizedString("status_item_accessibility_label", comment: "")
    statusItem.button?.setAccessibilityLabel(
      isStatusItemDisabled ? "\(base) — \(NSLocalizedString("status_item_disabled_accessibility_suffix", comment: ""))" : base
    )
  }

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if Self.isTesting {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
      // Start from a clean slate for the isolated testing preferences.
      UserDefaults.standard.removePersistentDomain(forName: Defaults.Keys.testingSuiteName)
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.p
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy {
      let shouldSkipPasteBoardQueue = PasteBoard.shared.consumePendingPasteCopy($0)
      if !shouldSkipPasteBoardQueue {
        AppState.shared.pasteBoardPopup.addCopiedItem($0)
      }
      History.shared.add($0)
    }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    updateStatusItemAccessibilityLabel()

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
        updateStatusItemAccessibilityLabel()
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
        updateStatusItemAccessibilityLabel()
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    let windowSize = Defaults[.windowSize]
    pasteBoardPanel = FloatingPanel(
      contentRect: savedPasteBoardContentRect ?? defaultPasteBoardContentRect,
      identifier: "\(Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy").PasteBoard",
      onClose: { AppState.shared.pasteBoardPopup.reset() }
    ) {
      PasteBoardView()
    }
    pasteBoardPanel.contentRectForOpen = { [weak self] in
      self?.savedPasteBoardContentRect
    }
    pasteBoardPanel.onContentRectChange = { [weak self] contentRect in
      self?.savePasteBoardContentRect(contentRect)
    }
    pasteBoardPanel.closesOnResignKey = false
    pasteBoardPanel.showsCloseButton = true
    pasteBoardPanel.level = .statusBar
    pasteBoardPanel.minSize = pasteBoardPanelSize
    pasteBoardPanel.maxSize = pasteBoardPanelMaxSize
    Defaults[.windowSize] = windowSize
  }

  private func savePasteBoardContentRect(_ contentRect: NSRect) {
    UserDefaults.standard.set(NSStringFromRect(contentRect), forKey: pasteBoardContentRectKey)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func ensureMigration(key: String, _ action: () -> Void) {
    if Defaults[.migrations][key] != true {
      action()
      Defaults[.migrations][key] = true
    }
  }

  @MainActor
  private func migrateUserDefaults() {
    ensureMigration(key: "2024-07-01-version-2") {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")
    }

    ensureMigration(key: "2025-07-04-add-jpeg-heic") {
      var types = Defaults[.enabledPasteboardTypes]
      if !types.isDisjoint(with: StorageType.images.types) {
        types.formUnion(StorageType.images.types)
      }
      Defaults[.enabledPasteboardTypes] = types
    }

    ensureMigration(key: "2026-08-12-cleanup-orphaned-history-item-contents") {
      _ = try? Storage.shared.cleanupOrphanedContents()
    }

    ensureMigration(key: "2026-08-31-sanitize-history-item-titles") {
      _ = try? Storage.shared.sanitizeTitles()
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin, .togglePreview]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
