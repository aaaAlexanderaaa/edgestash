import AppKit
import Carbon
import EdgeStashLogic

final class StashHotkeys {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var handlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var bundleIDsByID: [UInt32: String] = [:]
    private var registeredBundleIDs: Set<String> = []

    var onAppShortcut: ((String) -> Void)?
    var onTemporaryShortcut: (() -> Void)?

    private static let signature: OSType = 0x45445354

    deinit {
        stop()
    }

    func start() {
        installCarbonHandler()
        reload()
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleEvent(event) == true {
                return nil
            }
            return event
        }
    }

    func reload() {
        unregisterCarbonHotkeys()
        let preferences = Preferences.shared
        let bindings = preferences.appProfiles
            .compactMap { bundleID, settings -> (String, UInt16, UInt)? in
                guard settings.stashOn,
                      let chord = settings.chord else {
                    return nil
                }
                let normalized = AppShortcutPolicy.normalizedModifiers(chord.mods)
                guard normalized != 0 else { return nil }
                return (bundleID, chord.key, normalized)
            }
            .sorted { $0.0 < $1.0 }

        for (offset, binding) in bindings.enumerated() {
            let identifier = UInt32(offset + 1)
            var hotkeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.1),
                CarbonHotkeyPolicy.carbonModifiers(fromNSEvent: binding.2),
                EventHotKeyID(signature: Self.signature, id: identifier),
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyNoOptions),
                &hotkeyRef
            )
            guard status == noErr, let hotkeyRef else { continue }
            hotkeyRefs[identifier] = hotkeyRef
            bundleIDsByID[identifier] = binding.0
            if CarbonHotkeyPolicy.shouldExcludeFromEventMonitor(carbonHandlerInstalled: handlerRef != nil) {
                registeredBundleIDs.insert(binding.0)
            }
        }
    }

    func stop() {
        unregisterCarbonHotkeys()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func installCarbonHandler() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<StashHotkeys>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .handleCarbonEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            handlerRef = nil
        }
    }

    private func handleCarbonEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr,
              hotkeyID.signature == Self.signature,
              let bundleID = bundleIDsByID[hotkeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        DispatchQueue.main.async { [weak self] in self?.onAppShortcut?(bundleID) }
        return noErr
    }

    @discardableResult
    private func handleEvent(_ event: NSEvent) -> Bool {
        let modifiers = AppShortcutPolicy.normalizedModifiers(event.modifierFlags.rawValue)
        guard modifiers != 0 else { return false }
        let preferences = Preferences.shared
        if let storedModifiers = preferences.transientChordModifiers,
           let keyCode = preferences.transientChordKeyCode,
           AppShortcutPolicy.normalizedModifiers(storedModifiers) == modifiers,
           keyCode == event.keyCode {
            DispatchQueue.main.async { [weak self] in self?.onTemporaryShortcut?() }
            return true
        }
        for (bundleID, settings) in preferences.appProfiles where settings.stashOn {
            guard !registeredBundleIDs.contains(bundleID),
                  let chord = settings.chord,
                  AppShortcutPolicy.normalizedModifiers(chord.mods) == modifiers,
                  chord.key == event.keyCode else {
                continue
            }
            DispatchQueue.main.async { [weak self] in self?.onAppShortcut?(bundleID) }
            return true
        }
        return false
    }

    private func unregisterCarbonHotkeys() {
        hotkeyRefs.values.forEach { UnregisterEventHotKey($0) }
        hotkeyRefs.removeAll()
        bundleIDsByID.removeAll()
        registeredBundleIDs.removeAll()
    }
}
