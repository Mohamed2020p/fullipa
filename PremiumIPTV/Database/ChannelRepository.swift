import Foundation
import SQLite3

/// Pure SQLite3 wrapper — no third-party dependency required.
final class ChannelRepository {

    private var db: OpaquePointer?
    private let dbURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dbURL = dir.appendingPathComponent("iptv.db")
        openDatabase()
        createTableIfNeeded()
    }

    // MARK: - Open / Schema

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("ChannelRepository: Cannot open database")
        }
        // WAL mode for better concurrent reads
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
    }

    private func createTableIfNeeded() {
        let sql = """
        CREATE TABLE IF NOT EXISTS channels (
            id    INTEGER PRIMARY KEY AUTOINCREMENT,
            name  TEXT NOT NULL,
            url   TEXT NOT NULL UNIQUE,
            category TEXT NOT NULL,
            logo  TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_cat  ON channels(category);
        CREATE INDEX IF NOT EXISTS idx_name ON channels(name);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Write

    func clearAll() {
        sqlite3_exec(db, "DELETE FROM channels;", nil, nil, nil)
    }

    func insertBatch(_ channels: [Channel]) {
        guard !channels.isEmpty else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        let sql = "INSERT OR IGNORE INTO channels (name, url, category, logo) VALUES (?,?,?,?);"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        for ch in channels {
            sqlite3_bind_text(stmt, 1, (ch.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (ch.url as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (ch.category as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (ch.logo as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        sqlite3_finalize(stmt)
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }

    // MARK: - Read

    func getCategories() -> [String] {
        var list: [String] = []
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT DISTINCT category FROM channels ORDER BY category;", -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                list.append(String(cString: c))
            }
        }
        sqlite3_finalize(stmt)
        return list
    }

    func getTotalCount(category: String, search: String) -> Int {
        let (where_, args) = buildWhere(category: category, search: search)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM channels \(where_);", -1, &stmt, nil)
        bindArgs(stmt: stmt, args: args)
        var count = 0
        if sqlite3_step(stmt) == SQLITE_ROW { count = Int(sqlite3_column_int(stmt, 0)) }
        sqlite3_finalize(stmt)
        return count
    }

    func getChannelsPage(category: String, search: String, offset: Int, limit: Int) -> [Channel] {
        var list: [Channel] = []
        let (where_, args) = buildWhere(category: category, search: search)
        let sql = "SELECT name, url, category, logo FROM channels \(where_) ORDER BY name LIMIT \(limit) OFFSET \(offset);"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        bindArgs(stmt: stmt, args: args)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name     = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
            let url      = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let category = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let logo     = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            list.append(Channel(name: name, url: url, category: category, logo: logo))
        }
        sqlite3_finalize(stmt)
        return list
    }

    // MARK: - Helpers

    private func buildWhere(category: String, search: String) -> (String, [String]) {
        var conds: [String] = []
        var args:  [String] = []
        if category != "__all__" { conds.append("category = ?"); args.append(category) }
        if !search.isEmpty      { conds.append("name LIKE ?"); args.append("%\(search)%") }
        let clause = conds.isEmpty ? "" : "WHERE " + conds.joined(separator: " AND ")
        return (clause, args)
    }

    private func bindArgs(stmt: OpaquePointer?, args: [String]) {
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (arg as NSString).utf8String, -1, nil)
        }
    }

    deinit {
        sqlite3_close(db)
    }
}
