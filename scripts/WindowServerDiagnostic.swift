import AppKit
import Foundation

// A standalone, local diagnostic. Never linked into EdgeStash. Only the
// optional occlusion probe mutates windows, and those windows belong to it.
@_silgen_name("CGSMainConnectionID") private func connectionID() -> CInt
@_silgen_name("CGSSetWindowAlpha") private func setWindowAlpha(_ cid: CInt, _ wid: CInt, _ alpha: Float) -> CGError

private func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "DiagnosticCommand", code: Int(process.terminationStatus))
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func emit(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

private func rect(_ frame: CGRect) -> [String: CGFloat] {
    ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
}

private func edgeStashApps() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: "top.whatif.edgestash")
}

private func rescueSubjects() -> [[String: Any]] {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let store = support.appendingPathComponent("EdgeStash/store.json")
    let document = (try? Data(contentsOf: store)).flatMap {
        try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
    }
    let rescues = document?["rescues"] as? [[String: Any]] ?? []
    return rescues.compactMap { $0["subject"] as? [String: Any] }
}

private func snapshot() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let screens = NSScreen.screens
    let displays: [[String: Any]] = screens.map { screen in
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let id = number?.uint32Value ?? 0
        let mode = CGDisplayCopyDisplayMode(id)
        return ["displayID": id, "appKitFrame": rect(screen.frame), "quartzFrame": rect(CGDisplayBounds(id)),
                "scale": screen.backingScaleFactor, "pixelWidth": mode?.pixelWidth ?? 0,
                "pixelHeight": mode?.pixelHeight ?? 0, "refreshHz": mode?.refreshRate ?? 0,
                "mirrorOf": CGDisplayMirrorsDisplay(id)]
    }
    let apps = edgeStashApps()
    let appInfo: [[String: Any]] = apps.map { app in
        let bundle = app.bundleURL.flatMap(Bundle.init(url:))
        let modified = app.executableURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        let changed = modified.flatMap { date in app.launchDate.map { date > $0 } }
        return ["pid": app.processIdentifier,
                "launchDate": app.launchDate.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown",
                "onDiskVersion": bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown",
                "onDiskBuild": bundle?.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown",
                "executableChangedSinceLaunch": changed as Any? ?? NSNull()]
    }
    // Read only identity fields from rescue records. Do not copy preferences,
    // shortcuts, titles, filenames, display serials, or document content.
    let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    let windows = info ?? []
    func windowInfo(_ window: [String: Any]) -> [String: Any] {
        ["windowID": window[kCGWindowNumber as String] ?? 0,
         "pid": window[kCGWindowOwnerPID as String] ?? 0,
         "layer": window[kCGWindowLayer as String] ?? 0,
         "alpha": window[kCGWindowAlpha as String] ?? NSNull(),
         "onScreenListFlag": window[kCGWindowIsOnscreen as String] ?? false,
         "bounds": window[kCGWindowBounds as String] ?? NSNull()]
    }
    let appPIDs = Set(apps.map(\.processIdentifier))
    let overlays = windows.filter {
        appPIDs.contains(($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1)
    }.map(windowInfo)
    let subjects: [[String: Any]] = rescueSubjects().compactMap { subject in
        guard let id = subject["windowNumber"] as? NSNumber,
              let pid = subject["processID"] as? NSNumber,
              let bundleID = subject["bundleID"] as? String else { return nil }
        // A dossier is a recovery promise, not proof of a current session.
        // Even an identity match below is deliberately only a candidate.
        let processMatches = NSRunningApplication(processIdentifier: pid.int32Value)?.bundleIdentifier == bundleID
        var result: [String: Any] = ["windowID": id, "pid": pid, "bundleID": bundleID,
                                   "processBundleMatches": processMatches, "metadataFound": false]
        if processMatches, let window = windows.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber) == id
                && ($0[kCGWindowOwnerPID as String] as? NSNumber) == pid
        }) {
            result.merge(windowInfo(window), uniquingKeysWith: { _, new in new })
            result["metadataFound"] = true
        }
        return result
    }
    try emit(["schema": 1, "timestamp": ISO8601DateFormatter().string(from: Date()),
              "os": ProcessInfo.processInfo.operatingSystemVersionString,
              "displays": displays, "edgeStash": appInfo, "metadataQuerySucceeded": info != nil,
              "edgeStashWindows": overlays, "rescueCandidates": subjects,
              "limitations": ["On-screen metadata is not an occlusion, visibility, or rendering-cost measurement.",
                              "A missing window may be minimized or unavailable; do not infer its state.",
                              "On-disk version may differ from the running image; consult the sample header."]])
}

private func cpuSeconds(_ text: Substring) -> Double? {
    let pieces = text.split(separator: ":")
    guard !pieces.isEmpty else { return nil }
    var seconds = 0.0
    for piece in pieces {
        guard let value = Double(piece) else { return nil }
        seconds = seconds * 60 + value
    }
    return seconds
}

private func measure(seconds: Double, pids: [Int32]) throws {
    let started = ProcessInfo.processInfo.systemUptime
    var samples: [[String: Any]] = []
    var first: [Int32: (Double, Double)] = [:]
    var previous: [Int32: (Double, Double)] = [:]
    var totals: [String: Any] = [:]
    repeat {
        let before = ProcessInfo.processInfo.systemUptime
        let output = try command("/bin/ps", ["-p", pids.map(String.init).joined(separator: ","),
                                             "-o", "pid=,time=,stat="])
        let now = (before + ProcessInfo.processInfo.systemUptime) / 2
        var values: [[String: Any]] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 3, let pid = Int32(fields[0]), let cpu = cpuSeconds(fields[1]) else { continue }
            var value: [String: Any] = ["pid": pid, "cpuSeconds": cpu, "state": String(fields[2])]
            if let (priorTime, priorCPU) = previous[pid], now > priorTime, cpu >= priorCPU {
                value["intervalCPUPercent"] = (cpu - priorCPU) / (now - priorTime) * 100
            }
            if first[pid] == nil { first[pid] = (now, cpu) }
            previous[pid] = (now, cpu)
            values.append(value)
        }
        samples.append(["elapsed": now - started, "processes": values])
        let remaining = seconds - (ProcessInfo.processInfo.systemUptime - started)
        if remaining <= 0 { break }
        Thread.sleep(forTimeInterval: min(2, remaining))
    } while true
    for (pid, (lastTime, lastCPU)) in previous {
        if let (firstTime, firstCPU) = first[pid], lastTime > firstTime, lastCPU >= firstCPU {
            totals[String(pid)] = (lastCPU - firstCPU) / (lastTime - firstTime) * 100
        }
    }
    try emit(["requestedSeconds": seconds, "elapsed": ProcessInfo.processInfo.systemUptime - started,
              "averageCPUPercent": totals, "samples": samples,
              "units": "100% = one CPU core; cumulative CPU deltas divided by monotonic elapsed time"])
}

private final class ProbeWindow: NSWindow {
    // Normal AppKit placement constrains the title bar back onto the desktop.
    // Make the synthetic experiment's actual geometry match its declared one.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class OcclusionProbe: NSObject, NSApplicationDelegate {
    private var window: ProbeWindow!
    private var rows: [[String: Any]] = []
    private var stages: [(String, CGRect, () -> Void)] = []
    private var index = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.screens.min(by: { $0.frame.minX < $1.frame.minX }) else {
            NSApp.terminate(nil)
            return
        }
        // The leftmost display's left side is exposed. The probe never spans a
        // real shared seam and never changes any other application's windows.
        let lip = CGRect(x: screen.frame.minX - 598, y: screen.frame.midY - 200, width: 600, height: 400)
        let off = lip.offsetBy(dx: -62, dy: 0)
        window = ProbeWindow(contentRect: lip, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.title = "Disposable occlusion probe"
        stages = [
            ("cgs-zero-lip", lip, {
                self.window.setFrame(lip, display: false)
                self.setAlpha(0)
                self.window.orderFront(nil)
            }),
            ("appkit-zero-lip", lip, { self.window.alphaValue = 0 }),
            ("opaque-fully-offscreen", off, {
                self.window.setFrame(off, display: false)
                self.window.alphaValue = 1
            }),
            ("zero-fully-offscreen", off, { self.setAlpha(0) }),
            ("ordered-out", off, { self.window.orderOut(nil) }),
            ("minimized", lip, {
                self.window.setFrame(lip, display: false)
                self.setAlpha(0)
                self.window.orderFront(nil)
                self.window.miniaturize(nil)
            })
        ]
        next()
    }

    private func setAlpha(_ value: Float) {
        let result = setWindowAlpha(connectionID(), CInt(window.windowNumber), value)
        if result != .success {
            FileHandle.standardError.write(Data("Probe alpha write failed: \(result.rawValue)\n".utf8))
        }
    }

    private func next() {
        guard index < stages.count else {
            window.orderOut(nil)
            window.close()
            try? emit(["os": ProcessInfo.processInfo.operatingSystemVersionString, "stages": rows,
                       "limitations": "Synthetic app-owned windows; neither foreign-app behavior nor CPU causality is proved."])
            NSApp.terminate(nil)
            return
        }
        let (name, expected, change) = stages[index]
        change()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(self.window.windowNumber))
                as? [[String: Any]])?.first ?? [:]
            self.rows.append(["stage": name, "expectedFrame": rect(expected), "actualFrame": rect(self.window.frame),
                              "geometryMatches": self.window.frame == expected,
                              "occlusionVisible": self.window.occlusionState.contains(.visible),
                              "appkitVisible": self.window.isVisible, "minimized": self.window.isMiniaturized,
                              "serverAlpha": info[kCGWindowAlpha as String] ?? NSNull(),
                              "onScreenListFlag": info[kCGWindowIsOnscreen as String] ?? false])
            self.index += 1
            self.next()
        }
    }
}

@main
private enum Main {
    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            switch args.first {
            case "snapshot": try snapshot()
            case "subject-pids":
                let pids = rescueSubjects().compactMap { subject -> Int32? in
                    guard let pid = (subject["processID"] as? NSNumber)?.int32Value, pid > 0,
                          let bundleID = subject["bundleID"] as? String,
                          NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID else { return nil }
                    return pid
                }
                Set(pids).sorted().forEach { print($0) }
            case "measure":
                guard args.count >= 3, let seconds = Double(args[1]), seconds >= 2, seconds <= 60 else {
                    throw NSError(domain: "Use measure SECONDS PID... (2...60 seconds)", code: 1)
                }
                let pids = args.dropFirst(2).compactMap(Int32.init)
                guard pids.count == args.count - 2, pids.allSatisfy({ $0 > 0 }) else {
                    throw NSError(domain: "Invalid process id", code: 1)
                }
                try measure(seconds: seconds, pids: pids)
            case "occlusion-probe":
                let app = NSApplication.shared
                let probe = OcclusionProbe()
                app.delegate = probe
                app.run()
                withExtendedLifetime(probe) {}
            default: throw NSError(domain: "Use snapshot, measure SECONDS PID..., or occlusion-probe", code: 1)
            }
        } catch {
            FileHandle.standardError.write(Data("Diagnostic failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
