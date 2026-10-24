import Foundation

/// One JSON file with the rules every Isle store needs: an atomic save, a backup of the file that loaded,
/// an unreadable file kept aside and never overwritten, and owner-only permissions.
struct JSONFile<Value: Codable> {
    let url: URL

    private var folder: URL { url.deletingLastPathComponent() }
    private var stem: String { url.deletingPathExtension().lastPathComponent }

    /// Nil when there is no file. A file that does not decode moves aside as
    /// "<stem>.corrupt-<unix time>.json", and the result is nil. A good file is copied to "<stem>.backup.json".
    func load() -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let value = try Self.decoder.decode(Value.self, from: data)
            // One rolling copy of the last file that loaded, so a bad change can be undone by hand.
            write(data, to: folder.appendingPathComponent("\(stem).backup.json"))
            return value
        } catch {
            // Keep the unreadable file. A save must never overwrite the user's data.
            let aside = folder.appendingPathComponent("\(stem).corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            NSLog("Isle: could not read \(url.path) (\(error)). Moved it to \(aside.lastPathComponent).")
            return nil
        }
    }

    /// Never throws: a failed save is logged, and the data stays in memory.
    func save(_ value: Value) {
        do {
            write(try Self.encoder.encode(value), to: url)
        } catch {
            NSLog("Isle: could not encode \(url.path): \(error)")
        }
    }

    /// Owner-only: notes can hold private text. A folder that Isle creates is owner-only too, but Isle
    /// never changes a folder it did not create (`ISLE_DATA=/tmp/t.json` must not touch /tmp).
    private func write(_ data: Data, to target: URL) {
        do {
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            }
            try data.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            NSLog("Isle: could not save \(target.path): \(error)")
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
