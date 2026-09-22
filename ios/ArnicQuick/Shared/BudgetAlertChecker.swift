import Foundation
import UserNotifications

// ⚠️ SIN COMPILAR: escrito en Linux (sin Xcode). Ver docs/IOS.md.
// Target membership: Runner (App Intents/Atajos/Siri) y ArnicWidgets.

/// Revisa los presupuestos tras guardar un movimiento y notifica los que
/// acaban de cruzar 80% o 100% (mismo cálculo y misma tabla `budget_alerts`
/// que usan Dart y Kotlin: quien llegue primero "reclama" el aviso).
enum BudgetAlertChecker {
    static func checkAndNotify(_ db: OpaquePointer, currency: String) {
        let period = QuickDb.monthPeriodKey()
        guard let progressList = try? QuickDb.budgetsProgress(db) else { return }
        for progress in progressList {
            guard let level = progress.level else { continue }
            if QuickDb.markAlertIfNew(db, budgetId: progress.id, periodKey: period, level: level) {
                notify(progress, level: level, currency: currency)
            }
        }
    }

    private static func notify(_ p: QuickDb.BudgetProgress, level: String, currency: String) {
        let savings = p.kind == "savings"
        let title: String
        switch (savings, level) {
        case (true, "approaching"): title = "🐷 Casi llegas a tu meta de ahorro"
        case (true, _): title = "🎉 ¡Meta de ahorro cumplida!"
        case (false, "approaching"): title = "⚠️ Acercándote al límite: \(p.title)"
        default: title = "🚨 Límite alcanzado: \(p.title)"
        }
        let pct = Int(min(p.ratio * 100, 999).rounded())
        let body = savings
            ? "\(QuickDb.formatMoney(p.currentMinor, symbol: currency)) de \(QuickDb.formatMoney(p.amountMinor, symbol: currency)) (\(pct)%)"
            : "\(QuickDb.formatMoney(p.currentMinor, symbol: currency)) de \(QuickDb.formatMoney(p.amountMinor, symbol: currency)) gastados (\(pct)%)"

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Se pide permiso al crear el primer presupuesto (BudgetsScreen, Dart) vía
        // flutter_local_notifications; si el usuario lo negó, `add` no hace nada visible.
        let request = UNNotificationRequest(identifier: "\(p.id)-\(level)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
