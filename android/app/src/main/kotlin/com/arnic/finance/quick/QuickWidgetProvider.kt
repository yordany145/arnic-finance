package com.arnic.finance.quick

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.arnic.finance.MainActivity
import com.arnic.finance.R

/**
 * Widget de inicio: total gastado hoy + botones "Gasto" / "Ingreso".
 *
 * Límite de la plataforma: los widgets (RemoteViews) no admiten campos de texto,
 * así que los botones abren la hoja rápida en vez de teclear en el widget.
 * Se refresca al guardar (app y hoja rápida) y cada 30 min (mínimo de Android,
 * por eso al cambiar de día el "hoy" puede tardar en reiniciarse).
 */
class QuickWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, build(context)) }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_PINNED) refreshAll(context)
    }

    companion object {
        const val ACTION_PINNED = "com.arnic.finance.WIDGET_PINNED"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, QuickWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = build(context)
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_quick)

            var summary = context.getString(R.string.widget_open_app)
            (QuickDb.open(context) as? QuickDb.Status.Ready)?.let { ready ->
                ready.db.use { db ->
                    summary = context.getString(
                        R.string.widget_today_expenses,
                        QuickDb.formatMoney(QuickDb.todayExpenseMinor(db), QuickDb.currencySymbol(db)),
                    )
                }
            }
            views.setTextViewText(R.id.widget_summary, summary)

            views.setOnClickPendingIntent(R.id.widget_expense, activity(context, 10, QuickEntryActivity.intent(context, QuickEntryActivity.TYPE_EXPENSE)))
            views.setOnClickPendingIntent(R.id.widget_income, activity(context, 11, QuickEntryActivity.intent(context, QuickEntryActivity.TYPE_INCOME)))
            views.setOnClickPendingIntent(R.id.widget_summary, activity(context, 12, Intent(context, MainActivity::class.java)))
            return views
        }

        private fun activity(context: Context, code: Int, intent: Intent): PendingIntent =
            PendingIntent.getActivity(context, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
