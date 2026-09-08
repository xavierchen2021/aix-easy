import Foundation
import SQLite3

class NoteStore {
    private let db: SQLiteDatabase
    
    init(db: SQLiteDatabase) {
        self.db = db
        try? createTables()
        migrateAddDeletedColumns()
        migrateAddAIColumns()
        migrateAddPinnedAtColumn()
        migrateAddMemoryColumns()
        migrateAddGroupPasswordColumn()
        migrateAddActivityColumns()
        migrateAddTagColumn()
    }

    private func migrateAddTagColumn() {
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }

        var hasTag = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "tag" { hasTag = true }
            }
        }

        if !hasTag {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN tag TEXT;")
        }
    }

    private func migrateAddMemoryColumns() {
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }

        var hasIsMemory = false
        var hasIsInProgress = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "isMemory" { hasIsMemory = true }
                if colName == "isInProgress" { hasIsInProgress = true }
            }
        }

        if !hasIsMemory {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN isMemory INTEGER NOT NULL DEFAULT 0;")
        }
        if !hasIsInProgress {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN isInProgress INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private func migrateAddGroupPasswordColumn() {
        let checkSql = "PRAGMA table_info(NoteGroup);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }

        var hasIsLocked = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "isLocked" { hasIsLocked = true }
            }
        }

        if !hasIsLocked {
            try? db.execute(sql: "ALTER TABLE NoteGroup ADD COLUMN isLocked INTEGER NOT NULL DEFAULT 0;")
        }
    }
    
    private func migrateAddActivityColumns() {
        // Note 表：modifiedAt, completedAt
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }

        var hasModifiedAt = false
        var hasCompletedAt = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "modifiedAt" { hasModifiedAt = true }
                if colName == "completedAt" { hasCompletedAt = true }
            }
        }

        if !hasModifiedAt {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN modifiedAt REAL;")
        }
        if !hasCompletedAt {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN completedAt REAL;")
        }

        // NoteGroup 表：isActivityGroup
        let checkGroupSql = "PRAGMA table_info(NoteGroup);"
        guard let gStmt = try? db.prepareStatement(sql: checkGroupSql) else { return }
        defer { sqlite3_finalize(gStmt) }

        var hasIsActivityGroup = false
        while sqlite3_step(gStmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(gStmt, 1) {
                let colName = String(cString: name)
                if colName == "isActivityGroup" { hasIsActivityGroup = true }
            }
        }

        if !hasIsActivityGroup {
            try? db.execute(sql: "ALTER TABLE NoteGroup ADD COLUMN isActivityGroup INTEGER NOT NULL DEFAULT 0;")
        }
    }

    private func migrateAddDeletedColumns() {
        // 检查并添加 isDeleted 列
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }
        
        var hasIsDeleted = false
        var hasDeletedAt = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "isDeleted" { hasIsDeleted = true }
                if colName == "deletedAt" { hasDeletedAt = true }
            }
        }
        
        if !hasIsDeleted {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN isDeleted INTEGER NOT NULL DEFAULT 0;")
        }
        if !hasDeletedAt {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN deletedAt REAL;")
        }
    }
    
    private func migrateAddAIColumns() {
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }
        
        var hasIsAI = false
        var hasAiSessionId = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "isAI" { hasIsAI = true }
                if colName == "aiSessionId" { hasAiSessionId = true }
            }
        }
        
        if !hasIsAI {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN isAI INTEGER NOT NULL DEFAULT 0;")
        }
        if !hasAiSessionId {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN aiSessionId TEXT;")
        }
    }
    
    private func migrateAddPinnedAtColumn() {
        let checkSql = "PRAGMA table_info(Note);"
        guard let stmt = try? db.prepareStatement(sql: checkSql) else { return }
        defer { sqlite3_finalize(stmt) }
        
        var hasPinnedAt = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: name)
                if colName == "pinnedAt" { hasPinnedAt = true }
            }
        }
        
        if !hasPinnedAt {
            try? db.execute(sql: "ALTER TABLE Note ADD COLUMN pinnedAt REAL;")
        }
    }
    
    private func createTables() throws {
        let createNoteGroupTable = """
        CREATE TABLE IF NOT EXISTS NoteGroup (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            icon TEXT NOT NULL,
            isKnowledgeGroup INTEGER NOT NULL,
            sortOrder INTEGER NOT NULL
        );
        """
        
        let createNoteTable = """
        CREATE TABLE IF NOT EXISTS Note (
            id TEXT PRIMARY KEY NOT NULL,
            content TEXT NOT NULL,
            isCompleted INTEGER NOT NULL,
            createdAt REAL NOT NULL,
            colorHex TEXT,
            groupId TEXT NOT NULL,
            isKnowledge INTEGER NOT NULL,
            isMemory INTEGER NOT NULL DEFAULT 0,
            isInProgress INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (groupId) REFERENCES NoteGroup(id)
        );
        """
        
        try db.execute(sql: createNoteGroupTable)
        try db.execute(sql: createNoteTable)
    }
    
    // MARK: - Note Operations
    
    func insertNote(_ note: Note) throws {
        let sql = "INSERT OR REPLACE INTO Note (id, content, isCompleted, createdAt, colorHex, groupId, isKnowledge, isDeleted, deletedAt, isAI, aiSessionId, pinnedAt, isMemory, isInProgress, modifiedAt, completedAt, tag) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
        guard let statement = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(statement) }
        
        let idStr = note.id.uuidString as NSString
        sqlite3_bind_text(statement, 1, idStr.utf8String, -1, nil)
        
        let contentStr = note.content as NSString
        sqlite3_bind_text(statement, 2, contentStr.utf8String, -1, nil)
        
        sqlite3_bind_int(statement, 3, note.isCompleted ? 1 : 0)
        
        sqlite3_bind_double(statement, 4, note.createdAt.timeIntervalSinceReferenceDate)
        
        let colorStr = note.colorHex as NSString
        sqlite3_bind_text(statement, 5, colorStr.utf8String, -1, nil)
        
        let groupIdStr = note.groupId.uuidString as NSString
        sqlite3_bind_text(statement, 6, groupIdStr.utf8String, -1, nil)
        
        sqlite3_bind_int(statement, 7, note.isKnowledge ? 1 : 0)
        sqlite3_bind_int(statement, 8, note.isDeleted ? 1 : 0)
        
        if let deletedAt = note.deletedAt {
            sqlite3_bind_double(statement, 9, deletedAt.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        
        sqlite3_bind_int(statement, 10, note.isAI ? 1 : 0)
        
        if let aiSessionId = note.aiSessionId {
            let sessionIdStr = aiSessionId as NSString
            sqlite3_bind_text(statement, 11, sessionIdStr.utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 11)
        }
        
        if let pinnedAt = note.pinnedAt {
            sqlite3_bind_double(statement, 12, pinnedAt.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(statement, 12)
        }

        sqlite3_bind_int(statement, 13, note.isMemory ? 1 : 0)
        sqlite3_bind_int(statement, 14, note.isInProgress ? 1 : 0)
        
        if let modifiedAt = note.modifiedAt {
            sqlite3_bind_double(statement, 15, modifiedAt.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(statement, 15)
        }
        
        if let completedAt = note.completedAt {
            sqlite3_bind_double(statement, 16, completedAt.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(statement, 16)
        }

        if let tag = note.tag {
            let tagStr = tag as NSString
            sqlite3_bind_text(statement, 17, tagStr.utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func deleteNote(id: UUID) throws {
        let sql = "DELETE FROM Note WHERE id = ?;"
        guard let statement = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(statement) }
        
        let idStr = id.uuidString as NSString
        sqlite3_bind_text(statement, 1, idStr.utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func getAllNotes() -> [Note] {
        let sql = "SELECT id, content, isCompleted, createdAt, colorHex, groupId, isKnowledge, isDeleted, deletedAt, isAI, aiSessionId, pinnedAt, isMemory, isInProgress, modifiedAt, completedAt, tag FROM Note ORDER BY CASE WHEN pinnedAt IS NOT NULL THEN 0 ELSE 1 END, pinnedAt DESC, createdAt DESC;"
        guard let statement = try? db.prepareStatement(sql: sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        
        var notes: [Note] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idStr = Self.getString(statement, 0),
                  let id = UUID(uuidString: idStr),
                  let content = Self.getString(statement, 1) else {
                continue
            }
            
            let isCompleted = sqlite3_column_int(statement, 2) != 0
            let createdAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            
            // 如果数据库中没有颜色，使用默认紫色以确保存储和显示的稳定性
            let colorHex = Self.getString(statement, 4) ?? "#A855F7"
            
            let groupIdStr = Self.getString(statement, 5) ?? NoteGroup.defaultId.uuidString
            let groupId = UUID(uuidString: groupIdStr) ?? NoteGroup.defaultId
            
            let isKnowledge = sqlite3_column_int(statement, 6) != 0
            let isDeleted = sqlite3_column_int(statement, 7) != 0
            
            var deletedAt: Date? = nil
            if sqlite3_column_type(statement, 8) != SQLITE_NULL {
                deletedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 8))
            }
            
            let isAI = sqlite3_column_int(statement, 9) != 0
            let aiSessionId = Self.getString(statement, 10)
            
            var pinnedAt: Date? = nil
            if sqlite3_column_type(statement, 11) != SQLITE_NULL {
                pinnedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 11))
            }

            let isMemory = sqlite3_column_int(statement, 12) != 0
            let isInProgress = sqlite3_column_int(statement, 13) != 0
            
            var modifiedAt: Date? = nil
            if sqlite3_column_type(statement, 14) != SQLITE_NULL {
                modifiedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 14))
            }
            
            var completedAt: Date? = nil
            if sqlite3_column_type(statement, 15) != SQLITE_NULL {
                completedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 15))
            }

            let tag = Self.getString(statement, 16)
            
            let note = Note(id: id, content: content, isCompleted: isCompleted, createdAt: createdAt, colorHex: colorHex, groupId: groupId, isKnowledge: isKnowledge, isDeleted: isDeleted, deletedAt: deletedAt, isAI: isAI, aiSessionId: aiSessionId, pinnedAt: pinnedAt, isMemory: isMemory, isInProgress: isInProgress, modifiedAt: modifiedAt, completedAt: completedAt, tag: tag)
            notes.append(note)
        }
        
        return notes
    }
    
    // MARK: - Group Operations
    
    func insertGroup(_ group: NoteGroup) throws {
        let sql = "INSERT OR REPLACE INTO NoteGroup (id, name, icon, isKnowledgeGroup, sortOrder, isLocked, isActivityGroup) VALUES (?, ?, ?, ?, ?, ?, ?);"
        guard let statement = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(statement) }
        
        let idStr = group.id.uuidString as NSString
        sqlite3_bind_text(statement, 1, idStr.utf8String, -1, nil)
        
        let nameStr = group.name as NSString
        sqlite3_bind_text(statement, 2, nameStr.utf8String, -1, nil)
        
        let iconStr = group.icon as NSString
        sqlite3_bind_text(statement, 3, iconStr.utf8String, -1, nil)
        
        sqlite3_bind_int(statement, 4, group.isKnowledgeGroup ? 1 : 0)
        sqlite3_bind_int(statement, 5, Int32(group.sortOrder))
        sqlite3_bind_int(statement, 6, group.isLocked ? 1 : 0)
        sqlite3_bind_int(statement, 7, group.isActivityGroup ? 1 : 0)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func deleteGroup(id: UUID) throws {
        let sql = "DELETE FROM NoteGroup WHERE id = ?;"
        guard let statement = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(statement) }
        
        let idStr = id.uuidString as NSString
        sqlite3_bind_text(statement, 1, idStr.utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func getAllGroups() -> [NoteGroup] {
        let sql = "SELECT id, name, icon, isKnowledgeGroup, sortOrder, isLocked, isActivityGroup FROM NoteGroup ORDER BY sortOrder ASC;"
        guard let statement = try? db.prepareStatement(sql: sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        
        var groups: [NoteGroup] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idStr = Self.getString(statement, 0),
                  let id = UUID(uuidString: idStr),
                  let name = Self.getString(statement, 1),
                  let icon = Self.getString(statement, 2) else {
                continue
            }
            
            let isKnowledgeGroup = sqlite3_column_int(statement, 3) != 0
            let sortOrder = Int(sqlite3_column_int(statement, 4))
            let isLocked = sqlite3_column_int(statement, 5) != 0
            let isActivityGroup = sqlite3_column_int(statement, 6) != 0
            
            let group = NoteGroup(id: id, name: name, icon: icon, isKnowledgeGroup: isKnowledgeGroup, sortOrder: sortOrder, isLocked: isLocked, isActivityGroup: isActivityGroup)
            groups.append(group)
        }
        
        return groups
    }
    
    func updateGroupName(id: UUID, newName: String) throws {
        let sql = "UPDATE NoteGroup SET name = ? WHERE id = ?;"
        guard let statement = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(statement) }
        
        let nameStr = newName as NSString
        sqlite3_bind_text(statement, 1, nameStr.utf8String, -1, nil)
        
        let idStr = id.uuidString as NSString
        sqlite3_bind_text(statement, 2, idStr.utf8String, -1, nil)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    private static func getString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
    }

    /// Read groups and notes from an external sqlite DB file (read-only).
    static func readFrom(path: String) throws -> ([NoteGroup], [Note]) {
        let db = try SQLiteDatabase.open(path: path)
        defer { /* db will close when deallocated */ () }

        // Read groups
        var groups: [NoteGroup] = []
        let groupSQL = "SELECT id, name, icon, isKnowledgeGroup, sortOrder FROM NoteGroup ORDER BY sortOrder ASC;"
        guard let gStmt = try db.prepareStatement(sql: groupSQL) else { throw SQLiteError.prepare(message: db.errorMessage) }
        defer { sqlite3_finalize(gStmt) }
        while sqlite3_step(gStmt) == SQLITE_ROW {
            guard let idStrPtr = sqlite3_column_text(gStmt, 0) else { continue }
            let idStr = String(cString: UnsafeRawPointer(idStrPtr).assumingMemoryBound(to: CChar.self))
            guard let id = UUID(uuidString: idStr),
                  let namePtr = sqlite3_column_text(gStmt, 1),
                  let iconPtr = sqlite3_column_text(gStmt, 2) else { continue }
            let name = String(cString: UnsafeRawPointer(namePtr).assumingMemoryBound(to: CChar.self))
            let icon = String(cString: UnsafeRawPointer(iconPtr).assumingMemoryBound(to: CChar.self))
            let isKnowledgeGroup = sqlite3_column_int(gStmt, 3) != 0
            let sortOrder = Int(sqlite3_column_int(gStmt, 4))
            groups.append(NoteGroup(id: id, name: name, icon: icon, isKnowledgeGroup: isKnowledgeGroup, sortOrder: sortOrder))
        }

        // Read notes
        var notes: [Note] = []
        let noteSQL = "SELECT id, content, isCompleted, createdAt, colorHex, groupId, isKnowledge FROM Note ORDER BY createdAt DESC;"
        guard let nStmt = try db.prepareStatement(sql: noteSQL) else { throw SQLiteError.prepare(message: db.errorMessage) }
        defer { sqlite3_finalize(nStmt) }
        while sqlite3_step(nStmt) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(nStmt, 0),
                  let contentPtr = sqlite3_column_text(nStmt, 1) else { continue }
            let idStr = String(cString: UnsafeRawPointer(idPtr).assumingMemoryBound(to: CChar.self))
            guard let id = UUID(uuidString: idStr) else { continue }
            let content = String(cString: UnsafeRawPointer(contentPtr).assumingMemoryBound(to: CChar.self))
            let isCompleted = sqlite3_column_int(nStmt, 2) != 0
            let createdAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(nStmt, 3))
            
            // 如果数据库中没有颜色，使用默认值以确保存储和显示的稳定性
            let colorHex = Self.getString(nStmt, 4) ?? "#A855F7"
            
            let groupIdStr = sqlite3_column_text(nStmt, 5).flatMap { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } ?? NoteGroup.defaultId.uuidString
            let groupId = UUID(uuidString: groupIdStr) ?? NoteGroup.defaultId
            let isKnowledge = sqlite3_column_int(nStmt, 6) != 0
            notes.append(Note(id: id, content: content, isCompleted: isCompleted, createdAt: createdAt, colorHex: colorHex, groupId: groupId, isKnowledge: isKnowledge))
        }

        return (groups, notes)
    }
}
