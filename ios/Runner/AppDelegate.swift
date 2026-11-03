import Flutter
import GameController
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let tastatur = TastaturMelder()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "TastaturMelder") {
      FlutterEventChannel(name: "werkbank/tastatur", binaryMessenger: registrar.messenger())
        .setStreamHandler(tastatur)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Meldet, ob eine Hardware-Tastatur verbunden ist (Bluetooth, Smart Connector, USB).
///
/// GCKeyboard ist der einzige öffentliche Weg dafür auf iPadOS: UIKit selbst sagt
/// nur, ob die Bildschirmtastatur sichtbar ist, und die verschwindet auch, wenn
/// gerade kein Textfeld den Fokus hat.
final class TastaturMelder: NSObject, FlutterStreamHandler {
  private var senke: FlutterEventSink?
  private var beobachter: [NSObjectProtocol] = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    senke = events
    let zentrale = NotificationCenter.default
    for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
      beobachter.append(zentrale.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.melden()
      })
    }
    melden()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    beobachter.forEach(NotificationCenter.default.removeObserver)
    beobachter.removeAll()
    senke = nil
    return nil
  }

  private func melden() {
    senke?(GCKeyboard.coalesced != nil)
  }
}
