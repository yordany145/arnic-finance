package com.arnic.finance

import android.app.PendingIntent
import android.app.StatusBarManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import com.arnic.finance.quick.ExpenseTileService
import com.arnic.finance.quick.IncomeTileService
import com.arnic.finance.quick.QuickWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad de la app completa (Flutter). Sólo añade el canal que usa la pantalla
 * de Ajustes para ofrecer las tiles y el widget. El registro rápido NO pasa por
 * aquí: vive en [com.arnic.finance.quick.QuickEntryActivity].
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAddTile" -> requestAddTile(call.argument<Boolean>("expense") ?: true, result)
                "requestPinWidget" -> result.success(requestPinWidget())
                "refreshWidgets" -> {
                    QuickWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** `StatusBarManager.requestAddTileService` existe desde Android 13 (API 33). */
    private fun requestAddTile(expense: Boolean, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("unsupported")
            return
        }
        val manager = getSystemService(StatusBarManager::class.java)
        if (manager == null) {
            result.success("error")
            return
        }
        val service = if (expense) ExpenseTileService::class.java else IncomeTileService::class.java
        val label = getString(if (expense) R.string.tile_expense else R.string.tile_income)
        val icon = Icon.createWithResource(this, if (expense) R.drawable.ic_tile_expense else R.drawable.ic_tile_income)
        manager.requestAddTileService(ComponentName(this, service), label, icon, mainExecutor) { code ->
            result.success(
                when (code) {
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "already_added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "not_added"
                    else -> "error" // TILE_ADD_REQUEST_ERROR_*
                }
            )
        }
    }

    private fun requestPinWidget(): Boolean {
        val manager = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        val provider = ComponentName(this, QuickWidgetProvider::class.java)
        // Callback vacío: no necesitamos saber cuándo el usuario confirma.
        val callback = PendingIntent.getBroadcast(
            this, 0, Intent(this, QuickWidgetProvider::class.java).setAction(QuickWidgetProvider.ACTION_PINNED),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return manager.requestPinAppWidget(provider, null, callback)
    }

    companion object {
        const val CHANNEL = "com.arnic.finance/quick"
    }
}
