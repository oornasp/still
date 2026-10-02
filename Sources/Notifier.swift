import AppKit
import UserNotifications

/// End-of-session alerts are scheduled with the system up front, so they fire
/// on time even if the app is napping — no polling required.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, NSSoundDelegate {
    var onActivate: (() -> Void)?
    private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    private var sound: NSSound?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.isAuthorized = granted }
        }
    }

    func schedule(id: String, at date: Date, title: String, body: String, soundName: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let soundName { content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName + ".caf")) }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        // Permission can change in System Settings at any time; keep the fallback honest.
        center.getNotificationSettings { [weak self] settings in
            let ok = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { self?.isAuthorized = ok }
        }
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// In-app chime, used when notifications are not allowed.
    func play(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else { return }
        sound?.stop()
        sound = NSSound(contentsOf: url, byReference: true)
        sound?.delegate = self
        sound?.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if sound === self.sound { self.sound = nil }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.onActivate?() }
        completionHandler()
    }
}
