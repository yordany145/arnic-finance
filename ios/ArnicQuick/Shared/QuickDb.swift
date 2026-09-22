import Foundation
import SQLite3

// ⚠️ SIN COMPILAR: escrito en Linux (sin Xcode). Ver docs/IOS.md.
//
// Acceso mínimo al SQLite que crea y migra la app Flutter (drift).
// CONTRATO: tablas/columnas de lib/data/tables.dart. Sólo escribimos `transactions`
// y nunca creamos ni migramos el esquema. Target membership: Runner + ArnicWidgets.

enum QuickDb {
    /// Debe coincidir con `kAppGroupId` (lib/data/db_location.dart) y el entitlement.
    static let appGroup = "group.com.arnic.finance"
    static let supportedSchema: Int32 = 2 // = AppDatabase.kSchemaVersion
    static let pendingRouteKey = "pending_route"

    struct Category {
        let id: String
        let name: String
        let icon: String
        let type: String // "expense" | "income"
    }

    /// Presupuesto mensual + lo llevado este mes. Mismo cálculo que BudgetProgress (Dart/Kotlin).
    struct BudgetProgress {
        let id: String
        let kind: String // "category" | "overallExpense" | "savings"
        let title: String
        let amountMinor: Int64
        let currentMinor: Int64

        var ratio: Double { amountMinor == 0 ? 0 : Double(currentMinor) / Double(amountMinor) }
        var level: String? { // "approaching" | "reached" | nil
            if ratio >= 1.0 { return "reached" }
            if ratio >= 0.8 { return "approaching" }
            return nil
        }
    }

    enum DbError: Error {
        case missing      // la app aún no se abrió: no hay base ni categorías
        case appTooOld    // la base la creó una versión más nueva
        case sqlite(String)
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("arnic.db")
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { throw DbError.missing }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw DbError.missing
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)

        let version = try rows(db, "PRAGMA user_version").first.flatMap { Int32($0[0] ?? "") } ?? 0
        if version == 0 { throw DbError.missing }
        if version != supportedSchema { throw DbError.appTooOld }
        return try body(db)
    }

    /// Ejecuta una consulta y devuelve todas las columnas como texto.
    static func rows(_ db: OpaquePointer, _ sql: String, _ binds: [String] = []) throws -> [[String?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DbError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, transient)
        }
        var out: [[String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String?] = []
            for c in 0..<sqlite3_column_count(stmt) {
                row.append(sqlite3_column_text(stmt, c).map { String(cString: $0) })
            }
            out.append(row)
        }
        return out
    }

    /// Más usadas primero (mismo criterio que la app y que QuickDb.kt).
    static func categories(_ db: OpaquePointer, type: String? = nil) throws -> [Category] {
        let filter = type == nil ? "" : "AND c.type = ?"
        let sql = """
            SELECT c.id, c.name, c.icon, c.type FROM categories c
            LEFT JOIN transactions t ON t.category_id = c.id AND t.deleted_at IS NULL
            WHERE c.deleted_at IS NULL \(filter)
            GROUP BY c.id ORDER BY c.type, COUNT(t.id) DESC, c.sort_order ASC, c.name ASC
            """
        return try rows(db, sql, type.map { [$0] } ?? []).compactMap { r in
            guard let id = r[0], let name = r[1], let icon = r[2], let type = r[3] else { return nil }
            return Category(id: id, name: name, icon: icon, type: type)
        }
    }

    static func defaultAccountId(_ db: OpaquePointer) throws -> String? {
        let preferred = try rows(db, """
            SELECT a.id FROM accounts a WHERE a.deleted_at IS NULL AND a.id =
            (SELECT value FROM app_settings WHERE key = 'default_account_id')
            """)
        if let id = preferred.first?[0] { return id }
        return try rows(db, "SELECT id FROM accounts WHERE deleted_at IS NULL ORDER BY sort_order, created_at LIMIT 1").first?[0]
    }

    static func currencySymbol(_ db: OpaquePointer) -> String {
        (try? rows(db, "SELECT value FROM app_settings WHERE key = 'currency_symbol'").first?[0]) ?? nil ?? "RD$"
    }

    static func insertTransaction(_ db: OpaquePointer, type: String, amountMinor: Int64, categoryId: String, accountId: String) throws {
        let sql = """
            INSERT INTO transactions (id, type, amount_minor, category_id, account_id, note, occurred_at, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, NULL)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DbError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        sqlite3_bind_text(stmt, 1, UUID().uuidString.lowercased(), -1, transient)
        sqlite3_bind_text(stmt, 2, type, -1, transient)
        sqlite3_bind_int64(stmt, 3, amountMinor)
        sqlite3_bind_text(stmt, 4, categoryId, -1, transient)
        sqlite3_bind_text(stmt, 5, accountId, -1, transient)
        sqlite3_bind_int64(stmt, 6, now)
        sqlite3_bind_int64(stmt, 7, now)
        sqlite3_bind_int64(stmt, 8, now)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DbError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    /// Gastos de hoy (día local) en unidades menores.
    static func todayExpenseMinor(_ db: OpaquePointer) -> Int64 {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let ms = { (d: Date) in String(Int64(d.timeIntervalSince1970 * 1000)) }
        let r = try? rows(db, """
            SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
            WHERE type = 'expense' AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?
            """, [ms(start), ms(end)])
        return Int64(r?.first?[0] ?? "0") ?? 0
    }

    /// "2026-09". Igual que `monthPeriodKey` (Dart) y `QuickDb.monthPeriodKey` (Kotlin).
    static func monthPeriodKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    private static func monthRange(_ date: Date = Date()) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Presupuestos activos con su progreso del mes en curso.
    static func budgetsProgress(_ db: OpaquePointer) throws -> [BudgetProgress] {
        let (start, end) = monthRange()
        let ms = { (d: Date) in String(Int64(d.timeIntervalSince1970 * 1000)) }
        let budgetRows = try rows(db, "SELECT b.id, b.kind, b.amount_minor, b.category_id FROM budgets b WHERE b.deleted_at IS NULL")
        var out: [BudgetProgress] = []
        for row in budgetRows {
            guard let id = row[0], let kind = row[1], let amountText = row[2], let amount = Int64(amountText) else { continue }
            let categoryId = row[3]
            let title: String
            let current: Int64
            switch kind {
            case "savings":
                title = "Meta de ahorro"
                let sql = "SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE -amount_minor END), 0) FROM transactions WHERE deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?"
                current = try rows(db, sql, [ms(start), ms(end)]).first.flatMap { Int64($0[0] ?? "0") } ?? 0
            case "category":
                let nameRows = try rows(db, "SELECT name FROM categories WHERE id = ?", [categoryId ?? ""])
                title = nameRows.first?[0] ?? "Categoría"
                let sql = "SELECT COALESCE(SUM(amount_minor), 0) FROM transactions WHERE type = 'expense' AND deleted_at IS NULL AND category_id = ? AND occurred_at >= ? AND occurred_at < ?"
                current = try rows(db, sql, [categoryId ?? "", ms(start), ms(end)]).first.flatMap { Int64($0[0] ?? "0") } ?? 0
            default: // overallExpense
                title = "Límite general de gastos"
                let sql = "SELECT COALESCE(SUM(amount_minor), 0) FROM transactions WHERE type = 'expense' AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?"
                current = try rows(db, sql, [ms(start), ms(end)]).first.flatMap { Int64($0[0] ?? "0") } ?? 0
            }
            out.append(BudgetProgress(id: id, kind: kind, title: title, amountMinor: amount, currentMinor: current))
        }
        return out
    }

    /// `true` la primera vez que se cruza este nivel en este período (y lo deja registrado).
    static func markAlertIfNew(_ db: OpaquePointer, budgetId: String, periodKey: String, level: String) -> Bool {
        let sql = "INSERT INTO budget_alerts (budget_id, period_key, level, fired_at) VALUES (?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, budgetId, -1, transient)
        sqlite3_bind_text(stmt, 2, periodKey, -1, transient)
        sqlite3_bind_text(stmt, 3, level, -1, transient)
        sqlite3_bind_int64(stmt, 4, Int64(Date().timeIntervalSince1970 * 1000))
        return sqlite3_step(stmt) == SQLITE_DONE // false si choca con la clave primaria: ya se avisó.
    }

    static func formatMoney(_ minor: Int64, symbol: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        let whole = f.string(from: NSNumber(value: minor / 100)) ?? "\(minor / 100)"
        let cents = minor % 100
        return symbol + whole + (cents == 0 ? "" : "." + String(format: "%02d", cents))
    }
}
