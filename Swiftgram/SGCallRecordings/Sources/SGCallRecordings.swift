import Foundation

public enum SGCallRecordings {
    public static func directory(create: Bool) throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        var directory = documents.appendingPathComponent("DoxGram Call Recordings", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        }
        return directory
    }

    public static func files() -> [URL] {
        guard let directory = try? self.directory(create: false),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return [] }
        return files.filter {
            $0.pathExtension == "mp4" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
