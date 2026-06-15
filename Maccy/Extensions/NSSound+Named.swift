import AppKit.NSSound
import Defaults

enum SoundEffect: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case knock = "Knock.caf"
  case write = "Write.caf"
  case ceramic = "ceramic.mp3"
  case chapt = "chapt.mp3"
  case dodok = "dodok.mp3"
  case foldswitch = "foldswitch.mp3"
  case keyboard = "keyboard.mp3"
  case keydown = "keydown.mp3"
  case pentick = "pentick.mp3"
  case pentocking = "pentocking.mp3"
  case rifle = "rifle.mp3"
  case smalltick = "smalltick.mp3"
  case `switch` = "switch.mp3"
  case tiket = "tiket.mp3"
  case tirik = "tirik.mp3"

  var id: Self { self }

  var description: String {
    return resourceName.capitalized
  }

  var sound: NSSound? {
    return Self.sounds[self]
  }

  private var resourceName: String {
    return (rawValue as NSString).deletingPathExtension
  }

  private var resourceExtension: String {
    return (rawValue as NSString).pathExtension
  }

  private static let sounds: [SoundEffect: NSSound] = {
    let pairs = SoundEffect.allCases.compactMap { effect -> (SoundEffect, NSSound)? in
      guard let url = Bundle.main.url(forResource: effect.resourceName, withExtension: effect.resourceExtension),
            let sound = NSSound(contentsOf: url, byReference: true) else {
        return nil
      }

      return (effect, sound)
    }

    return Dictionary(uniqueKeysWithValues: pairs)
  }()
}

extension NSSound {
  static let knock = NSSound(
    contentsOf: Bundle.main.url(forResource: "Knock", withExtension: "caf")!, byReference: true)
  static let write = NSSound(
    contentsOf: Bundle.main.url(forResource: "Write", withExtension: "caf")!, byReference: true)
}
