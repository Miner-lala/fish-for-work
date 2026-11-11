import Foundation

/// The app's single JSON file in ~/Library/Application Support/XiaoYuGan, with one backup copy per day.
final class Store {
    let directory: URL
    private let dataFile: URL
    private let logFile: URL
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("XiaoYuGan", isDirectory: true)
        dataFile = directory.appendingPathComponent("data.json")
        logFile = directory.appendingPathComponent("app.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The saved data as a JavaScript literal, or nil when there is nothing usable yet.
    /// An unreadable file is moved aside rather than overwritten.
    func bootJSON() -> String? {
        guard let data = try? Data(contentsOf: dataFile), !data.isEmpty else { return nil }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil, let text = String(data: data, encoding: .utf8) else {
            let aside = directory.appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: dataFile, to: aside)
            log("data.json was unreadable, moved to \(aside.lastPathComponent)")
            return nil
        }
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    func save(_ json: String) {
        guard let data = json.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else {
            log("refused to save data that is not JSON")
            return
        }
        backUpOncePerDay()
        do {
            try data.write(to: dataFile, options: .atomic)
        } catch {
            log("save failed: \(error.localizedDescription)")
        }
    }

    private func backUpOncePerDay() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataFile.path) else { return }
        let folder = directory.appendingPathComponent("backups", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("data-\(dayFormatter.string(from: Date())).json")
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.copyItem(at: dataFile, to: target)
        let copies = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("data-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for old in copies.dropLast(30) { try? fm.removeItem(at: old) }
    }

    func log(_ line: String) {
        guard let bytes = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n".data(using: .utf8) else { return }
        if let size = (try? FileManager.default.attributesOfItem(atPath: logFile.path))?[.size] as? Int, size > 512_000 {
            try? FileManager.default.removeItem(at: logFile)
        }
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(bytes)
            try? handle.close()
        } else {
            try? bytes.write(to: logFile)
        }
    }
}
