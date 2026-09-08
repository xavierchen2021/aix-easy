import Foundation
import SQLite3

/// 常用文件/文件夹 SQLite 存储
class FavoriteStore {
    private let db: SQLiteDatabase
    
    init(db: SQLiteDatabase) {
        self.db = db
        try? createTable()
    }
    
    private func createTable() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS FavoriteItem (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            isDirectory INTEGER NOT NULL,
            createdAt REAL NOT NULL
        );
        """
        try db.execute(sql: sql)
    }
    
    // MARK: - CRUD
    
    func insert(_ item: FavoriteItem) throws {
        let sql = "INSERT OR REPLACE INTO FavoriteItem (id, name, path, isDirectory, createdAt) VALUES (?, ?, ?, ?, ?);"
        guard let stmt = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.name as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (item.path as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, item.isDirectory ? 1 : 0)
        sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSinceReferenceDate)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func delete(id: UUID) throws {
        let sql = "DELETE FROM FavoriteItem WHERE id = ?;"
        guard let stmt = try db.prepareStatement(sql: sql) else { return }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func fetchAll() throws -> [FavoriteItem] {
        let sql = "SELECT id, name, path, isDirectory, createdAt FROM FavoriteItem ORDER BY createdAt DESC;"
        guard let stmt = try db.prepareStatement(sql: sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        var items: [FavoriteItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let nameCStr = sqlite3_column_text(stmt, 1),
                  let pathCStr = sqlite3_column_text(stmt, 2) else { continue }
            
            let idStr = String(cString: idCStr)
            guard let id = UUID(uuidString: idStr) else { continue }
            
            let name = String(cString: nameCStr)
            let path = String(cString: pathCStr)
            let isDirectory = sqlite3_column_int(stmt, 3) != 0
            let createdAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 4))
            
            items.append(FavoriteItem(id: id, name: name, path: path, isDirectory: isDirectory, createdAt: createdAt))
        }
        return items
    }
}
