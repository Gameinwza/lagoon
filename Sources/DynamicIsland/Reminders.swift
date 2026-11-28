import AppKit

struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var fireAt: Date
}

/// Countdown timers and clock-time reminders. One Timer for the earliest item (no polling);
/// items are saved so they survive a relaunch, and anything missed while quit rings on launch.
@MainActor
final class Reminders: ObservableObject {
    static let shared = Reminders()
    static let presets = [5, 10, 15, 25, 60]  // minutes

    @Published private(set) var items: [Reminder] = []
    /// Alerts waiting to be dismissed, oldest first (several can come due together).
    @Published private(set) var ringing: [Reminder] = []
    private var timer: Timer?
    private var hideRing: DispatchWorkItem?
    private let key = "reminders"

    private init() {
        if Pref.bool(Pref.timers), let d = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([Reminder].self, from: d) {
            items = saved
        }
        // Run-loop timers pause while the Mac sleeps, so re-aim after waking.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Reminders.shared.schedule() }
        }
        schedule()
    }

    var next: Reminder? { items.min { $0.fireAt < $1.fireAt } }
    var sorted: [Reminder] { items.sorted { $0.fireAt < $1.fireAt } }

    func start(minutes: Int, label: String = "") {
        let text = label.trimmingCharacters(in: .whitespaces)
        add(Reminder(label: text.isEmpty ? "\(minutes) นาที" : text, fireAt: .now + TimeInterval(minutes * 60)))
    }

    func remind(_ label: String, at time: Date) {
        let text = label.trimmingCharacters(in: .whitespaces)
        add(Reminder(label: text.isEmpty ? "ถึงเวลาแล้ว" : text, fireAt: Self.nextOccurrence(of: time)))
    }

    func cancel(_ r: Reminder) { items.removeAll { $0.id == r.id }; changed() }

    /// Dismiss the alert on screen; the next one (if any) takes its place.
    func stopRinging() { if !ringing.isEmpty { ringing.removeFirst() }; if ringing.isEmpty { hideRing?.cancel() } }

    /// Feature switch: off clears everything and stops the timer.
    func applyEnabled() {
        if !Pref.bool(Pref.timers) { items = []; ringing = []; hideRing?.cancel(); save() }
        schedule()
    }

    /// The next time the clock shows `time`'s hour and minute (today, or tomorrow if it has passed).
    nonisolated static func nextOccurrence(of time: Date, after now: Date = .now, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.nextDate(after: now, matching: c, matchingPolicy: .nextTime) ?? now
    }

    private func add(_ r: Reminder) {
        guard Pref.bool(Pref.timers), items.count < 20 else { return }  // cap: nobody needs more at once
        items.append(r); changed()
    }

    private func changed() { save(); schedule() }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }

    func schedule() {
        timer?.invalidate(); timer = nil
        guard Pref.bool(Pref.timers), let n = next else { return }
        let t = Timer(fire: max(n.fireAt, .now), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { Reminders.shared.fire() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        let due = items.filter { $0.fireAt <= .now.addingTimeInterval(0.5) }
        if !due.isEmpty {
            items.removeAll { r in due.contains { $0.id == r.id } }
            ringing += due.sorted { $0.fireAt < $1.fireAt }
            NSSound(named: "Glass")?.play()
            hideRing?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.ringing = [] }
            hideRing = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: w)  // don't sit there forever
            save()
        }
        schedule()
    }

    /// "4:59" or "1:04:59".
    nonisolated static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
