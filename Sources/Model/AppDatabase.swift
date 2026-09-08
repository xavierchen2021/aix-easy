import Foundation

@MainActor
class AppDatabase {
    static let shared = AppDatabase()
    static let databasePathKey = "DatabasePathKey"

    private(set) var db: SQLiteDatabase
    private(set) var noteStore: NoteStore
    private(set) var settingsStore: SettingsStore
    private(set) var favoriteStore: FavoriteStore

    static var defaultDBPath: String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory.appendingPathComponent("notes.sqlite").path
    }

    private(set) var dbPath: String

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.databasePathKey)
        let dbPath = saved ?? Self.defaultDBPath

        do {
            db = try SQLiteDatabase.open(path: dbPath)
            self.dbPath = dbPath
            noteStore = NoteStore(db: db)
            settingsStore = SettingsStore(db: db)
            favoriteStore = FavoriteStore(db: db)
        } catch {
            fatalError("Error initializing database: \(error)")
        }
    }

    /// Switch the running database to a different file path. This will re-create store instances.
    func switchDatabase(to path: String) throws {
        let newDb = try SQLiteDatabase.open(path: path)
        // Replace stores with new DB
        self.db = newDb
        self.dbPath = path
        self.noteStore = NoteStore(db: newDb)
        self.settingsStore = SettingsStore(db: newDb)
        self.favoriteStore = FavoriteStore(db: newDb)

        UserDefaults.standard.set(path, forKey: Self.databasePathKey)
        NotificationCenter.default.post(name: .databaseDidChange, object: nil)
    }

    /// Backup current database file (and related -wal/-shm files) and return backup path for the main DB file.
    func backupCurrentDatabase() throws -> String {
        let fm = FileManager.default
        let current = self.dbPath
        guard fm.fileExists(atPath: current) else {
            throw NSError(domain: "AppDatabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前数据库文件未找到：\(current)"])
        }

        let url = URL(fileURLWithPath: current)
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backupName = "\(url.lastPathComponent).bak.\(ts)"
        let backupURL = url.deletingLastPathComponent().appendingPathComponent(backupName)

        try fm.copyItem(at: url, to: backupURL)

        // Copy possible -wal and -shm files
        for suffix in ["-wal", "-shm"] {
            let extraPath = current + suffix
            if fm.fileExists(atPath: extraPath) {
                let extraURL = URL(fileURLWithPath: extraPath)
                let extraBackupName = "\(extraURL.lastPathComponent).bak.\(ts)"
                let extraBackupURL = backupURL.deletingLastPathComponent().appendingPathComponent(extraBackupName)
                try fm.copyItem(at: extraURL, to: extraBackupURL)
            }
        }

        return backupURL.path
    }

    /// Copy current database (and wal/shm) to target path. Parent directory will be created if needed.
    func copyCurrentDatabase(to targetPath: String) throws {
        let fm = FileManager.default
        let current = self.dbPath
        let curURL = URL(fileURLWithPath: current)
        let targetURL = URL(fileURLWithPath: targetPath)
        let targetDir = targetURL.deletingLastPathComponent()

        if !fm.fileExists(atPath: targetDir.path) {
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }

        try fm.copyItem(at: curURL, to: targetURL)

        for suffix in ["-wal", "-shm"] {
            let curExtra = URL(fileURLWithPath: current + suffix)
            if fm.fileExists(atPath: curExtra.path) {
                let targetExtra = URL(fileURLWithPath: targetPath + suffix)
                try fm.copyItem(at: curExtra, to: targetExtra)
            }
        }
    }

    /// Backup current DB then copy it to target path
    func backupAndCopyCurrentDatabase(to targetPath: String) throws {
        _ = try backupCurrentDatabase()
        try copyCurrentDatabase(to: targetPath)
    }

    /// Import groups and notes from another sqlite database file into the current DB.
    func importFrom(path: String) throws {
        let (groups, notes) = try NoteStore.readFrom(path: path)
        for g in groups {
            try noteStore.insertGroup(g)
        }
        for n in notes {
            try noteStore.insertNote(n)
        }
    }
}

extension Notification.Name {
    static let databaseDidChange = Notification.Name("DatabaseDidChange")
}
