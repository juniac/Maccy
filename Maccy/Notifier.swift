import AppKit
import UserNotifications

class Notifier {
  private static var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
  private static var lastSound: NSSound?

  // NSSound ignores play() while already playing, so rapid copy/paste
  // silently drops sounds. Keep a single playback: stop the previous
  // sound and restart the current one.
  private static func playSound(_ sound: NSSound?) {
    DispatchQueue.main.async {
      lastSound?.stop()
      lastSound = sound
      sound?.play()
    }
  }

  static func authorize() {
    center.requestAuthorization(options: [.alert, .sound]) { _, error in
      if error != nil {
        NSLog("Failed to authorize notifications: \(String(describing: error))")
      }
    }
  }

  static func notify(body: String?, sound: NSSound?) {
    guard let body else { return }

    authorize()

    center.getNotificationSettings { settings in
      guard (settings.authorizationStatus == .authorized) ||
            (settings.authorizationStatus == .provisional) else { return }

      let content = UNMutableNotificationContent()
      if settings.alertSetting == .enabled {
        content.body = body
      }

      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      center.add(request) { error in
        if error != nil {
          NSLog("Failed to deliver notification: \(String(describing: error))")
        } else {
          if settings.soundSetting == .enabled {
            playSound(sound)
          }
        }
      }
    }
  }
}
