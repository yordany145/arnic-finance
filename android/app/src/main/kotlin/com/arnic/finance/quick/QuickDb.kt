package com.arnic.finance.quick

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale
import java.util.UUID

/**
 * Acceso mínimo al SQLite que crea y migra la app Flutter (drift).
 *
 * CONTRATO: tablas/columnas definidas en lib/data/tables.dart. Sólo escribimos
 * `transactions`; jamás creamos ni migramos el esquema (eso es cosa de la app).
 * Si [SUPPORTED_SCHEMA] no coincide con `PRAGMA user_version`, no escribimos.
 */
object QuickDb {
    const val SUPPORTED_SCHEMA = 2
    private const val FILE_NAME = "arnic.db" // = kDatabaseFileName (Dart)

    class Category(val id: String, val name: String, val icon: String)

    /** Presupuesto mensual + lo llevado este mes. Mismo cálculo que BudgetProgress (Dart). */
    class BudgetProgress(
        val id: String,
        val kind: String, // "category" | "overallExpense" | "savings"
        val title: String,
        val amountMinor: Long,
        val currentMinor: Long,
    ) {
        val ratio: Double get() = if (amountMinor == 0L) 0.0 else currentMinor.toDouble() / amountMinor
        val isOver: Boolean get() = kind != "savings" && ratio >= 1.0

        /** "approaching" | "reached" | null. */
        val level: String?
            get() = when {
                ratio >= 1.0 -> "reached"
                ratio >= 0.8 -> "approaching"
                else -> null
            }
    }

    sealed interface Status {
        /** La app aún no se abrió: no existe la base (ni las categorías). */
        data object Missing : Status
        /** La base la creó una versión más nueva de la app. */
        data object AppTooOld : Status
        class Ready(val db: SQLiteDatabase) : Status
    }

    /** `Context.filesDir` == `getApplicationSupportDirectory()` de path_provider. */
    fun file(context: Context): File = File(context.filesDir, FILE_NAME)

    fun open(context: Context): Status {
        val f = file(context)
        if (!f.exists()) return Status.Missing
        val db = try {
            SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (e: Exception) {
            return Status.Missing
        }
        val version = db.version
        if (version != SUPPORTED_SCHEMA) {
            db.close()
            // 0 = archivo vacío/sin migrar (la app aún no terminó de crearlo).
            return if (version == 0) Status.Missing else Status.AppTooOld
        }
        db.enableWriteAheadLogging() // mismo modo que usa Dart (PRAGMA journal_mode=WAL)
        db.setForeignKeyConstraintsEnabled(true)
        // Igual que NativeDatabase (Dart) y sqlite3_busy_timeout (Swift): sin esto,
        // si la app Flutter está escribiendo justo cuando se guarda desde la hoja
        // rápida, esta conexión falla al instante con SQLITE_BUSY en vez de esperar.
        db.rawQuery("PRAGMA busy_timeout = 5000", null).use { it.moveToFirst() }
        return Status.Ready(db)
    }

    /** Más usadas primero (mismo criterio que DriftCategoryRepository.watchByUsage). */
    fun categories(db: SQLiteDatabase, type: String): List<Category> {
        val out = ArrayList<Category>()
        db.rawQuery(
            "SELECT c.id, c.name, c.icon FROM categories c " +
                "LEFT JOIN transactions t ON t.category_id = c.id AND t.deleted_at IS NULL " +
                "WHERE c.type = ? AND c.deleted_at IS NULL " +
                "GROUP BY c.id ORDER BY COUNT(t.id) DESC, c.sort_order ASC, c.name ASC",
            arrayOf(type),
        ).use { c -> while (c.moveToNext()) out += Category(c.getString(0), c.getString(1), c.getString(2)) }
        return out
    }

    /** Cuenta predeterminada (ajuste) o, si no existe/está borrada, la primera activa. */
    fun defaultAccountId(db: SQLiteDatabase): String? {
        db.rawQuery(
            "SELECT a.id FROM accounts a WHERE a.deleted_at IS NULL AND a.id = " +
                "(SELECT value FROM app_settings WHERE key = 'default_account_id')", null,
        ).use { if (it.moveToFirst()) return it.getString(0) }
        db.rawQuery("SELECT id FROM accounts WHERE deleted_at IS NULL ORDER BY sort_order, created_at LIMIT 1", null)
            .use { if (it.moveToFirst()) return it.getString(0) }
        return null
    }

    fun currencySymbol(db: SQLiteDatabase): String {
        db.rawQuery("SELECT value FROM app_settings WHERE key = 'currency_symbol'", null)
            .use { if (it.moveToFirst()) return it.getString(0) }
        return "RD$"
    }

    fun insertTransaction(db: SQLiteDatabase, type: String, amountMinor: Long, categoryId: String, accountId: String) {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("id", UUID.randomUUID().toString())
            put("type", type)
            put("amount_minor", amountMinor)
            put("category_id", categoryId)
            put("account_id", accountId)
            putNull("note")
            put("occurred_at", now)
            put("created_at", now)
            put("updated_at", now)
            putNull("deleted_at")
        }
        db.insertOrThrow("transactions", null, values)
    }

    /** Gastos de hoy (día local), en unidades menores. */
    fun todayExpenseMinor(db: SQLiteDatabase): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val start = cal.timeInMillis
        cal.add(Calendar.DAY_OF_MONTH, 1)
        db.rawQuery(
            "SELECT COALESCE(SUM(amount_minor), 0) FROM transactions " +
                "WHERE type = 'expense' AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?",
            arrayOf(start.toString(), cal.timeInMillis.toString()),
        ).use { return if (it.moveToFirst()) it.getLong(0) else 0L }
    }

    /** "2026-09". Igual que `monthPeriodKey` (lib/domain/budget.dart): no cambiar el formato. */
    fun monthPeriodKey(cal: Calendar = Calendar.getInstance()): String =
        "%04d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)

    private fun monthRangeMillis(): Pair<Long, Long> {
        val cal = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val start = cal.timeInMillis
        cal.add(Calendar.MONTH, 1)
        return start to cal.timeInMillis
    }

    /** Presupuestos activos con su progreso del mes en curso (mismo cálculo que
     * DriftBudgetRepository.watchProgress). */
    fun budgetsProgress(db: SQLiteDatabase): List<BudgetProgress> {
        val (start, end) = monthRangeMillis()
        val out = ArrayList<BudgetProgress>()
        db.rawQuery(
            "SELECT b.id, b.kind, b.amount_minor, b.category_id, c.name, c.icon " +
                "FROM budgets b LEFT JOIN categories c ON c.id = b.category_id WHERE b.deleted_at IS NULL",
            null,
        ).use { rows ->
            while (rows.moveToNext()) {
                val id = rows.getString(0)
                val kind = rows.getString(1)
                val amount = rows.getLong(2)
                val categoryId = rows.getString(3)
                val title = when (kind) {
                    "category" -> rows.getString(4) ?: "Categoría"
                    "overallExpense" -> "Límite general de gastos"
                    else -> "Meta de ahorro"
                }
                val current = when (kind) {
                    "savings" -> db.rawQuery(
                        "SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor ELSE -amount_minor END), 0) " +
                            "FROM transactions WHERE deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?",
                        arrayOf(start.toString(), end.toString()),
                    ).use { if (it.moveToFirst()) it.getLong(0) else 0L }
                    "category" -> db.rawQuery(
                        "SELECT COALESCE(SUM(amount_minor), 0) FROM transactions WHERE type = 'expense' " +
                            "AND deleted_at IS NULL AND category_id = ? AND occurred_at >= ? AND occurred_at < ?",
                        arrayOf(categoryId, start.toString(), end.toString()),
                    ).use { if (it.moveToFirst()) it.getLong(0) else 0L }
                    else -> db.rawQuery(
                        "SELECT COALESCE(SUM(amount_minor), 0) FROM transactions WHERE type = 'expense' " +
                            "AND deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?",
                        arrayOf(start.toString(), end.toString()),
                    ).use { if (it.moveToFirst()) it.getLong(0) else 0L }
                }
                out += BudgetProgress(id, kind, title, amount, current)
            }
        }
        return out
    }

    /** `true` la primera vez que se cruza este nivel en este período (y lo deja registrado). */
    fun markAlertIfNew(db: SQLiteDatabase, budgetId: String, periodKey: String, level: String): Boolean {
        return try {
            val values = ContentValues().apply {
                put("budget_id", budgetId)
                put("period_key", periodKey)
                put("level", level)
                put("fired_at", System.currentTimeMillis())
            }
            db.insertOrThrow("budget_alerts", null, values)
            true
        } catch (e: SQLiteConstraintException) {
            false // chocó con la clave primaria budgetId+periodKey+level: ya se avisó.
        }
        // Cualquier otro error (BD cerrada, disco lleno, etc.) se propaga: no debe
        // confundirse con "ya notificado". Lo atrapa el try/catch de quien llama
        // (QuickEntryActivity.save / BudgetAlertChecker), que ya asume que un aviso
        // fallido no debe impedir que el movimiento guardado se vea.
    }

    // ── Reglas del teclado y formato (mismas que lib/core/money.dart) ───────────

    fun applyKey(current: String, key: String): String {
        if (key == "⌫") return current.dropLast(1)
        if (key == ".") return when {
            current.contains('.') -> current
            current.isEmpty() -> "0."
            else -> "$current."
        }
        val dot = current.indexOf('.')
        if (dot >= 0) return if (current.length - dot - 1 >= 2) current else current + key
        if (current == "0") return if (key == "0") current else key
        return if (current.length >= 9) current else current + key
    }

    fun parseMinor(text: String): Long {
        if (text.isEmpty()) return 0
        val parts = text.split('.')
        val whole = parts[0].ifEmpty { "0" }.toLongOrNull() ?: 0L
        val frac = if (parts.size > 1) parts[1].padEnd(2, '0').substring(0, 2).toLongOrNull() ?: 0L else 0L
        return whole * 100 + frac
    }

    fun formatMoney(minor: Long, symbol: String): String {
        val cents = minor % 100
        val whole = NumberFormat.getIntegerInstance(Locale.US).format(minor / 100)
        return symbol + whole + if (cents == 0L) "" else "." + cents.toString().padStart(2, '0')
    }

    /** "1234.5" → "1,234.5" (sólo para mostrar). */
    fun groupForDisplay(raw: String): String {
        val dot = raw.indexOf('.')
        val whole = if (dot < 0) raw else raw.substring(0, dot)
        val frac = if (dot < 0) "" else raw.substring(dot)
        val sb = StringBuilder()
        whole.forEachIndexed { i, ch ->
            if (i > 0 && (whole.length - i) % 3 == 0) sb.append(',')
            sb.append(ch)
        }
        return sb.toString() + frac
    }
}
