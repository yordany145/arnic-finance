package com.arnic.finance.quick

import android.app.PendingIntent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Tile del panel de ajustes rápidos. Al pulsarla abre [QuickEntryActivity]
 * colapsando el panel (`startActivityAndCollapse`).
 *
 * Por qué una Activity y no `showDialog()`: la Activity permite un teclado
 * propio y diseño a medida, y se comporta igual con cualquier fabricante.
 * `showDialog` tampoco funciona con el dispositivo bloqueado.
 *
 * Privacidad: con pantalla bloqueada y PIN/huella activos, se pide desbloquear
 * (`unlockAndRun`) antes de mostrar la hoja.
 */
abstract class BaseQuickTileService(private val type: String) : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE // es un botón, no un interruptor
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val open = { launch() }
        if (isLocked && isSecure) unlockAndRun(open) else open()
    }

    private fun launch() {
        val intent = QuickEntryActivity.intent(this, type)
        if (Build.VERSION.SDK_INT >= 34) {
            // Android 14+: sólo se admite la variante con PendingIntent.
            val pending = PendingIntent.getActivity(
                this, if (type == QuickEntryActivity.TYPE_EXPENSE) 1 else 2, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

class ExpenseTileService : BaseQuickTileService(QuickEntryActivity.TYPE_EXPENSE)
class IncomeTileService : BaseQuickTileService(QuickEntryActivity.TYPE_INCOME)
