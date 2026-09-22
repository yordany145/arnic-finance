package com.arnic.finance.quick

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.arnic.finance.R
import kotlin.math.roundToInt

/**
 * Revisa los presupuestos tras guardar un movimiento desde la hoja rápida y
 * notifica los que acaban de cruzar 80% o 100% (mismo cálculo y misma tabla
 * `budget_alerts` que usa la app Flutter: quien llegue primero "reclama" el
 * aviso, así que nunca se duplica entre procesos).
 */
object BudgetAlertChecker {
    private const val CHANNEL_ID = "arnic_budgets"

    fun checkAndNotify(context: Context, db: SQLiteDatabase, currency: String) {
        if (!hasPermission(context)) return // el usuario aún no lo concedió; no insistimos aquí.
        val period = QuickDb.monthPeriodKey()
        for (progress in QuickDb.budgetsProgress(db)) {
            val level = progress.level ?: continue
            if (QuickDb.markAlertIfNew(db, progress.id, period, level)) {
                notify(context, progress, level, currency)
            }
        }
    }

    private fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun notify(context: Context, p: QuickDb.BudgetProgress, level: String, currency: String) {
        ensureChannel(context)
        val savings = p.kind == "savings"
        val title = when {
            savings && level == "approaching" -> context.getString(R.string.notif_approaching_savings)
            savings -> context.getString(R.string.notif_reached_savings)
            level == "approaching" -> context.getString(R.string.notif_approaching_expense, p.title)
            else -> context.getString(R.string.notif_reached_expense, p.title)
        }
        val pct = (p.ratio * 100).coerceAtMost(999.0).roundToInt()
        val body = context.getString(
            if (savings) R.string.notif_body_savings else R.string.notif_body_expense,
            QuickDb.formatMoney(p.currentMinor, currency),
            QuickDb.formatMoney(p.amountMinor, currency),
            pct,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        val id = (p.id.hashCode() * 31 + level.hashCode()) and 0x7fffffff
        try {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, notification)
        } catch (e: SecurityException) {
            // Permiso revocado entre la comprobación y el envío: no hay más que hacer aquí.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.notif_channel_budgets), NotificationManager.IMPORTANCE_HIGH)
                .apply { description = context.getString(R.string.notif_channel_budgets_desc) },
        )
    }
}
