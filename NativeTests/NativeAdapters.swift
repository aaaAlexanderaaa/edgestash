import AppKit
import EdgeStashLogic

@main struct NativeAdapters {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures += 1; fputs("FAIL: \(message)\n", stderr) }
        }
        func store(_ name: String) -> URL { root.appendingPathComponent(name).appendingPathComponent("store.json") }
        let record = RescueDossier(subject: .init(bundleID: "test.synthetic", processID: 42424, windowNumber: 42),
            placement: .init(edge: 0, frame: StoredGeometry(CGRect(x: 10, y: 10, width: 600, height: 400)),
                             display: StoredGeometry(CGRect(x: 0, y: 0, width: 1920, height: 1080))),
            landing: StoredGeometry(CGPoint(x: 100, y: 100)), recordedAt: Date(timeIntervalSince1970: 1000))
        var document = StoredDocument()
        document.apps["test.synthetic"] = AppStashProfile(stashOn: true, tint: "adaptive")
        document.rescues = [record]
        let url = store("independent")
        expect(PreferenceStore.save(document, at: url), "initial settings save is acknowledged")
        expect(PreferenceStore.saveRescues([record], at: url), "rescue has an independent acknowledged journal")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var apps = json["apps"] as! [String: [String: Any]]
        apps["test.synthetic"]!["chordScope"] = "future-value"
        apps["invalid"] = ["stashOn": "not-a-bool"]
        json["apps"] = apps
        try JSONSerialization.data(withJSONObject: json).write(to: url, options: .atomic)
        let recovered = PreferenceStore.load(at: url)
        expect(recovered.apps.count == 1 && recovered.apps["test.synthetic"]?.chordScope == nil,
               "unknown scope defaults independently and malformed profile cannot erase good profiles")
        expect(recovered.rescues == [record], "ordinary profile decoding cannot discard rescue")
        expect(PreferenceStore.save(recovered, at: url)
            && FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("store.damaged.json").path),
               "partial input is preserved before a repaired document replaces it")
        try Data("broken JSON".utf8).write(to: url, options: .atomic)
        expect(PreferenceStore.load(at: url).rescues == [record], "damaged main document still loads independent rescue")

        let journal = url.deletingLastPathComponent().appendingPathComponent("rescues.json")
        expect(PreferenceStore.saveRescues([record], at: url), "valid journal remains writable after damaged settings")
        try Data("broken journal".utf8).write(to: journal, options: .atomic)
        expect(PreferenceStore.load(at: url).rescues == [record], "validated previous journal recovers damage")
        expect(PreferenceStore.saveRescues([record], at: url), "valid recovery copy permits repair without losing records")
        expect(PreferenceStore.saveRescues([], at: url), "completed recovery can durably clear the journal")
        expect(PreferenceStore.load(at: url).rescues == [], "an acknowledged empty journal overrides stale settings records")

        let redundant = store("latest-complete-copy")
        var secondRecord = record
        secondRecord.subject.windowNumber = 43
        expect(PreferenceStore.saveRescues([record], at: redundant)
            && PreferenceStore.saveRescues([record, secondRecord], at: redundant),
               "both first and second hidden windows have acknowledged rescue records")
        try Data("corrupt current".utf8).write(to: redundant.deletingLastPathComponent().appendingPathComponent("rescues.json"))
        expect(PreferenceStore.load(at: redundant).rescues == [record, secondRecord],
               "recovery copy includes the newest hidden window, not only the preceding set")
        expect(!PreferenceStore.saveRescues([secondRecord], replacing: [], at: redundant)
            && PreferenceStore.load(at: redundant).rescues == [record, secondRecord],
               "a process that failed its initial read cannot overwrite newly readable, unobserved rescue records")
        let concurrent = store("concurrent-compare-and-save")
        expect(PreferenceStore.saveRescues([], at: concurrent), "concurrent fixture starts empty")
        let resultLock = NSLock()
        var acknowledged = 0
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let saved = PreferenceStore.saveRescues([index == 0 ? record : secondRecord], replacing: [], at: concurrent)
            resultLock.lock()
            if saved { acknowledged += 1 }
            resultLock.unlock()
        }
        expect(acknowledged == 1 && PreferenceStore.load(at: concurrent).rescues?.count == 1,
               "concurrent compare-and-save cannot acknowledge two hides while dropping one record")

        let bad = store("unreadable-journal")
        expect(PreferenceStore.save(document, at: bad), "bad-journal fixture settings saved")
        try Data("bad".utf8).write(to: bad.deletingLastPathComponent().appendingPathComponent("rescues.json"))
        expect(!PreferenceStore.saveRescues([record], at: bad), "unreadable journal without backup blocks a new hide")
        expect(PreferenceStore.save(document, at: bad) && PreferenceStore.rescueSaveFailed,
               "an ordinary settings save cannot clear an unresolved rescue failure")
        let preserved = try Data(contentsOf: bad.deletingLastPathComponent().appendingPathComponent("rescues.json"))
        expect(preserved == Data("bad".utf8),
               "failed rescue read is not overwritten with assumed empty state")

        let locked = store("read-only")
        expect(PreferenceStore.save(document, at: locked), "read-only fixture starts with a valid rescue")
        let directory = locked.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        expect(!PreferenceStore.saveRescues([record], at: locked), "filesystem rejection is a failed hide acknowledgement")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        expect(PreferenceStore.load(at: locked).rescues == [record], "failed migration preserves the original rescue")
        let blockedMain = store("failed-settings")
        try FileManager.default.createDirectory(at: blockedMain, withIntermediateDirectories: true)
        expect(!PreferenceStore.save(document, at: blockedMain), "an invalid main-document path fails explicitly")
        // A valid independent rescue copy can still be saved; settings failure
        // must remain visible rather than being cleared by that success.
        try JSONEncoder().encode([record]).write(to: blockedMain.deletingLastPathComponent().appendingPathComponent("rescues.json"))
        expect(PreferenceStore.saveRescues([record], at: blockedMain) && PreferenceStore.lastSaveFailed,
               "rescue success cannot clear the independent main-settings failure")
        expect(KeyGlyphs.label(for: 4) == "H" && KeyGlyphs.label(for: 5) == "G" && KeyGlyphs.label(for: 11) == "B",
               "physical G/H/B shortcuts display the correct ANSI labels")

        // Own AppKit panels only: no foreign AX reads/writes, permission prompts,
        // system preferences, window titles, screen capture, or actual app engine.
        _ = NSApplication.shared
        let marker = StashMarkerWindow()
        var presses = 0
        marker.onClicked = { presses += 1 }
        expect(marker.contentView?.accessibilityPerformPress() == true && presses == 1,
               "a rail's native accessibility press reaches its stash action")
        let pin = StashPinWindow()
        pin.onToggle = { presses += 1 }
        expect(pin.contentView?.accessibilityPerformPress() == true && presses == 2,
               "pin accessibility press reaches its toggle")
        let member = NSObject()
        let identifier = ObjectIdentifier(member)
        let strip = StashMergeStrip()
        strip.onClickSegment = { if $0 == identifier { presses += 1 } }
        let segment = StashMergeSegmentModel(id: identifier, color: .white, material: .glass,
            title: "Synthetic", icon: nil, slotRect: CGRect(x: 2, y: 0, width: 5, height: 90), kind: .outerStrip)
        strip.present(StashMergeStripModel(windowFrame: CGRect(x: 0, y: 0, width: 21, height: 90), edge: .left,
            trackRect: segment.slotRect, hitRect: CGRect(x: 0, y: 0, width: 21, height: 90), segments: [segment],
            labelWindowFrame: CGRect(x: 0, y: 0, width: 240, height: 90), labelSegments: [segment],
            activeID: nil, hoveredID: nil, showsLabels: false))
        let child = strip.contentView?.accessibilityChildren()?.first as? NSAccessibilityElement
        expect(child?.accessibilityPerformPress() == true && presses == 3,
               "a merged segment has its own native accessibility action")
        strip.orderOut(nil)
        marker.orderOut(nil)
        pin.conceal()
        if failures > 0 { exit(1) }
        print("Native adapter checks passed (isolated storage and own AppKit controls).")
    }
}
