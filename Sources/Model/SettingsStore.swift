import Foundation
import SQLite3

/// SQLite 临时回调，告诉 SQLite 在执行后立即复制字符串数据
/// 这样就不需要担心传入指针的生命周期问题
private let SQLITE_TRANSIENT: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in }

class SettingsStore {
    private let db: SQLiteDatabase
    
    init(db: SQLiteDatabase) {
        self.db = db
        try? createTable()
    }
    
    private func createTable() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS AppConfig (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        """
        do {
            try db.execute(sql: sql)
            print("[SettingsStore] createTable 成功")
        } catch {
            print("[SettingsStore] createTable 失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    func saveConfig(key: String, value: String) throws {
        let sql = "INSERT OR REPLACE INTO AppConfig (key, value) VALUES (?, ?);"
        let statement = try db.prepareStatement(sql: sql)
        defer { sqlite3_finalize(statement) }
        
        // 使用strdup分配持久内存，SQLite会自动释放
        let keyPtr = strdup(key)
        let valuePtr = strdup(value)
        
        defer {
            free(keyPtr)
            free(valuePtr)
        }
        
        sqlite3_bind_text(statement, 1, keyPtr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, valuePtr, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: db.errorMessage)
        }
    }
    
    func loadConfig(key: String) -> String? {
        let sql = "SELECT value FROM AppConfig WHERE key = ?;"
        do {
            let statement = try db.prepareStatement(sql: sql)
            defer { sqlite3_finalize(statement) }
            
            // 使用strdup分配持久内存，SQLite会自动释放
            let keyPtr = strdup(key)
            defer { free(keyPtr) }
            
            sqlite3_bind_text(statement, 1, keyPtr, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                return getString(statement, 0)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    private func getString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
    }
    
    func isFirstLaunch() -> Bool {
        return loadConfig(key: "isFirstLaunch") == nil
    }
    
    func setFirstLaunchCompleted() {
        try? saveConfig(key: "isFirstLaunch", value: "false")
    }
}
