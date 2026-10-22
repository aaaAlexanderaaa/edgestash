import Foundation
import MachO

/// A package-level diagnostic flag is independent of compiler optimization.
/// Ordinary Release never evaluates snapshots or creates the log directory.
enum StashDiagnostics {
    static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.object(forInfoDictionaryKey: "EdgeStashRuntimeDiagnostics") as? Bool == true
        #endif
    }()
    private static let writer: StashDiagnosticWriter? = isEnabled ? StashDiagnosticWriter(directory:
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/EdgeStash", isDirectory: true)) : nil

    static func start() {
        record("app.start", [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "configuration": Bundle.main.object(forInfoDictionaryKey: "EdgeStashBuildConfiguration") as? String ?? "unknown",
            "executableUUID": executableUUID
        ])
    }

    static func record(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:],
                       throttleKey: String? = nil) {
        guard isEnabled else { return }
        writer?.append(event, fields: fields(), throttleKey: throttleKey)
    }

    static func flush() {
        writer?.flush()
    }

    /// Read the loaded Mach-O, so replacing the app on disk cannot make an
    /// old process report the new executable's build identity.
    private static var executableUUID: String {
        guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else { return "unknown" }
        let raw = UnsafeRawPointer(header)
        var offset = MemoryLayout<mach_header_64>.size
        for _ in 0..<header.pointee.ncmds {
            let command = raw.advanced(by: offset).load(as: load_command.self)
            guard command.cmdsize >= MemoryLayout<load_command>.size else { return "unknown" }
            if command.cmd == LC_UUID {
                return UUID(uuid: raw.advanced(by: offset).load(as: uuid_command.self).uuid).uuidString
            }
            offset += Int(command.cmdsize)
        }
        return "unknown"
    }
}

/// One serial writer, two files of at most 2 MiB each. No titles, keystrokes,
/// window contents, or network transport. Repeated AX failures are rate-limited.
final class StashDiagnosticWriter {
    private let directory: URL
    private let maximumBytes: UInt64
    private let queue = DispatchQueue(label: "top.whatif.edgestash.diagnostics", qos: .utility)
    private let runID = UUID().uuidString
    private let formatter = ISO8601DateFormatter()
    private var handle: FileHandle?
    private var size: UInt64 = 0
    private var lastFailures: [String: TimeInterval] = [:]
    private var reportedFailure = false

    init(directory: URL, maximumBytes: UInt64 = 2 * 1_024 * 1_024) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func append(_ event: String, fields: [String: Any], throttleKey: String? = nil) {
        let date = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            if let key = throttleKey {
                if let previous = lastFailures[key], uptime - previous < 5 { return }
                if lastFailures.count >= 512 { lastFailures.removeAll() }
                lastFailures[key] = uptime
            }
            var row = fields
            row["event"] = event
            row["time"] = formatter.string(from: date)
            row["uptime"] = uptime
            row["run"] = runID
            row["process"] = ProcessInfo.processInfo.processIdentifier
            do {
                var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                data.append(0x0a)
                guard data.count <= maximumBytes else { return }
                try openIfNeeded()
                if size + UInt64(data.count) > maximumBytes { try rotate() }
                try handle?.write(contentsOf: data)
                size += UInt64(data.count)
            } catch {
                if !reportedFailure {
                    let failure = error as NSError
                    NSLog("[EdgeStash] Diagnostic log unavailable: %@ %ld", failure.domain, failure.code)
                    reportedFailure = true
                }
            }
        }
    }

    func flush() { queue.sync {} }

    private var current: URL { directory.appendingPathComponent("runtime.jsonl") }

    private func openIfNeeded() throws {
        guard handle == nil else { return }
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        if !files.fileExists(atPath: current.path) {
            guard files.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        handle = try FileHandle(forWritingTo: current)
        size = try handle!.seekToEnd()
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let previous = directory.appendingPathComponent("runtime.previous.jsonl")
        let files = FileManager.default
        if files.fileExists(atPath: previous.path) { try files.removeItem(at: previous) }
        try files.moveItem(at: current, to: previous)
        try openIfNeeded()
    }
}
