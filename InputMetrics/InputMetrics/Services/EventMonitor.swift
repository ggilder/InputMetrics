@preconcurrency import Cocoa
import CoreGraphics
import Carbon.HIToolbox
import os

@MainActor
class EventMonitor {
    static let shared = EventMonitor()

    private var eventTap: CFMachPort?
    private var retryTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 30

    private var firstActiveAt: String?
    private var lastActiveAt: String?
    private var currentDate: String?

    private var lastEventTime: Date = Date()
    private var activeSeconds: TimeInterval = 0
    private let idleThreshold: TimeInterval = 300

    private var appBuffer: [String: (name: String, keystrokes: Int)] = [:]
    private var appPersistTimer: Timer?

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    var isKeyboardPermissionLikelyMissing: Bool {
        !CGPreflightListenEventAccess()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    func start() {
        startAppTracking()
        startSleepWakeObservers()
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
        if createAndStartEventTap() { return }

        AppLogger.events.warning("Event tap creation failed -- input monitoring permission likely not granted")
        AppLogger.events.info("Please enable InputMetrics in System Settings > Privacy & Security > Input Monitoring")

        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = "InputMetrics needs Input Monitoring permission to track keyboard events.\n\n1. Open System Settings\n2. Go to Privacy & Security > Input Monitoring\n3. Enable InputMetrics\n\nThe app will start automatically once permission is granted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }

        startRetryTimer()
    }

    func stop() {
        appPersistTimer?.invalidate()
        appPersistTimer = nil
        persistAppUsage()
        retryTimer?.invalidate()
        retryTimer = nil
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        sleepObserver = nil
        wakeObserver = nil
        guard let eventTap = eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        AppLogger.events.info("Event monitoring stopped")
    }

    private func createAndStartEventTap() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                       (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let activeTap = EventMonitor.shared.eventTap {
                        CGEvent.tapEnable(tap: activeTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                EventMonitor.shared.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return false
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLogger.events.info("Event monitoring started")
        return true
    }

    func startAppTracking() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.persistAppUsage()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        appPersistTimer = timer
    }

    private func persistAppUsage() {
        let today = DateHelper.todayString()
        for (bundleId, data) in appBuffer {
            DatabaseManager.shared.updateAppUsage(
                date: today,
                bundleId: bundleId,
                appName: data.name,
                keystrokes: data.keystrokes
            )
        }
        appBuffer.removeAll()
    }

    private func startRetryTimer() {
        retryCount = 0
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                self.retryCount += 1
                if self.createAndStartEventTap() {
                    AppLogger.events.info("Event monitoring started after permission grant")
                    timer.invalidate()
                    self.retryTimer = nil
                } else if self.retryCount >= self.maxRetries {
                    AppLogger.events.warning("Permission not granted after \(self.maxRetries) retries -- please restart the app")
                    timer.invalidate()
                    self.retryTimer = nil
                }
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func startSleepWakeObservers() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    private func handleSleep() {
        KeyboardTracker.shared.persistData()
        persistAppUsage()
    }

    private func handleWake() {
        lastEventTime = Date()
        let today = Self.dateFormatter.string(from: Date())
        if currentDate != today {
            firstActiveAt = nil
            lastActiveAt = nil
            currentDate = today
        }
    }

    func getActivityTimes() -> (first: String?, last: String?) {
        (firstActiveAt, lastActiveAt)
    }

    func getAppUsageSnapshot() -> [String: (name: String, keystrokes: Int)] {
        appBuffer
    }

    /// Returns whole active minutes and keeps the leftover seconds for the next call.
    func getAndResetActiveMinutes() -> Int {
        let minutes = Int(activeSeconds / 60)
        activeSeconds -= TimeInterval(minutes * 60)
        return minutes
    }

    nonisolated private static func isModifierPress(keyCode: Int, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case kVK_Shift, kVK_RightShift: return flags.contains(.maskShift)
        case kVK_Control, kVK_RightControl: return flags.contains(.maskControl)
        case kVK_Option, kVK_RightOption: return flags.contains(.maskAlternate)
        case kVK_Command, kVK_RightCommand: return flags.contains(.maskCommand)
        case kVK_Function: return flags.contains(.maskSecondaryFn)
        case kVK_CapsLock: return true
        default: return false
        }
    }

    nonisolated static func isCountedKeystroke(type: CGEventType, isAutoRepeat: Bool) -> Bool {
        type == .keyDown && !isAutoRepeat
    }

    nonisolated private func handleEvent(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isAutoRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        MainActor.assumeIsolated {
            let now = Date()
            let today = Self.dateFormatter.string(from: now)
            if currentDate != today {
                firstActiveAt = nil
                lastActiveAt = nil
                currentDate = today
            }
            let timeString = Self.timeFormatter.string(from: now)
            if firstActiveAt == nil {
                firstActiveAt = timeString
            }
            lastActiveAt = timeString

            let elapsed = now.timeIntervalSince(lastEventTime)
            if elapsed < idleThreshold {
                activeSeconds += elapsed
            }
            lastEventTime = now

            switch type {
            case .keyDown:
                if Self.isCountedKeystroke(type: type, isAutoRepeat: isAutoRepeat) {
                    KeyboardTracker.shared.trackKeystroke(keyCode: keyCode, modifierFlags: flags)
                }

            case .flagsChanged:
                if Self.isModifierPress(keyCode: keyCode, flags: flags) {
                    KeyboardTracker.shared.trackModifierPress(keyCode: keyCode)
                }

            default:
                break
            }

            if let app = NSWorkspace.shared.frontmostApplication,
               let bundleId = app.bundleIdentifier {
                let name = app.localizedName ?? bundleId
                var entry = appBuffer[bundleId] ?? (name: name, keystrokes: 0)
                entry.name = name

                switch type {
                case .keyDown:
                    if Self.isCountedKeystroke(type: type, isAutoRepeat: isAutoRepeat) {
                        entry.keystrokes += 1
                    }
                default:
                    break
                }

                appBuffer[bundleId] = entry
            }
        }
    }
}
