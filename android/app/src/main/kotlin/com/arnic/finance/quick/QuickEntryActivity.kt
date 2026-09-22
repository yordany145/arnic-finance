package com.arnic.finance.quick

import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.GridLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.app.Activity
import com.arnic.finance.MainActivity
import com.arnic.finance.R

/**
 * Hoja de registro rápido. Es una Activity nativa (Views, sin Flutter) para que
 * abra en una fracción de segundo desde la tile, el widget o el atajo del icono.
 *
 * Flujo: monto → (categoría ya preseleccionada) → GUARDAR.
 */
class QuickEntryActivity : Activity() {
    private var db: SQLiteDatabase? = null
    private var type = TYPE_EXPENSE
    private var amount = ""
    private var categories: List<QuickDb.Category> = emptyList()
    private var categoryId: String? = null
    private var accountId: String? = null
    private var currency = "RD$"

    private lateinit var sheet: LinearLayout
    private lateinit var amountView: TextView
    private lateinit var btnExpense: Button
    private lateinit var btnIncome: Button
    private lateinit var chipRow: LinearLayout
    private lateinit var saveButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_quick_entry)
        bindViews()
        type = normalizeType(intent.getStringExtra(EXTRA_TYPE))

        when (val status = QuickDb.open(this)) {
            is QuickDb.Status.Ready -> {
                db = status.db
                currency = QuickDb.currencySymbol(status.db)
                accountId = QuickDb.defaultAccountId(status.db)
                setupEntry()
            }
            QuickDb.Status.Missing -> showMessage(getString(R.string.quick_open_app_first), openApp = true)
            QuickDb.Status.AppTooOld -> showMessage(getString(R.string.quick_update_app), openApp = true)
        }
    }

    /** Si la hoja ya está abierta y se pulsa la otra tile, sólo cambia el tipo. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (db != null) selectType(normalizeType(intent.getStringExtra(EXTRA_TYPE)))
    }

    override fun onDestroy() {
        db?.close()
        super.onDestroy()
    }

    private fun bindViews() {
        val root = findViewById<View>(R.id.quick_root)
        sheet = findViewById(R.id.quick_sheet)
        amountView = findViewById(R.id.quick_amount)
        btnExpense = findViewById(R.id.quick_type_expense)
        btnIncome = findViewById(R.id.quick_type_income)
        chipRow = findViewById(R.id.quick_chips)
        saveButton = findViewById(R.id.quick_save)

        root.setOnClickListener { finishAndRemoveTask() } // tocar fuera cierra
        sheet.setOnClickListener { /* absorbe toques dentro de la hoja */ }
        // Android 15+ dibuja de borde a borde: deja espacio para la barra de gestos.
        val basePadding = sheet.paddingBottom
        @Suppress("DEPRECATION")
        sheet.setOnApplyWindowInsetsListener { v, insets ->
            v.setPadding(v.paddingLeft, v.paddingTop, v.paddingRight, basePadding + insets.systemWindowInsetBottom)
            insets
        }
    }

    private fun setupEntry() {
        btnExpense.setOnClickListener { selectType(TYPE_EXPENSE) }
        btnIncome.setOnClickListener { selectType(TYPE_INCOME) }
        buildKeypad()
        saveButton.setOnClickListener { save() }
        selectType(type)
    }

    private fun selectType(newType: String) {
        type = newType
        val database = db ?: return
        categories = QuickDb.categories(database, type)
        categoryId = categories.firstOrNull()?.id // la más usada, ya elegida
        val expense = type == TYPE_EXPENSE
        val accent = getColor(if (expense) R.color.arnic_expense else R.color.arnic_income)
        styleToggle(btnExpense, selected = expense, color = getColor(R.color.arnic_expense))
        styleToggle(btnIncome, selected = !expense, color = getColor(R.color.arnic_income))
        amountView.setTextColor(accent)
        saveButton.background = rounded(accent, 18f)
        saveButton.setTextColor(getColor(R.color.arnic_on_accent))
        renderChips()
        renderAmount()
    }

    private fun renderChips() {
        chipRow.removeAllViews()
        for (c in categories) {
            val chip = TextView(this).apply {
                text = "${c.icon}  ${c.name}"
                textSize = 16f
                setPadding(dp(14), dp(10), dp(14), dp(10))
                setOnClickListener {
                    categoryId = c.id
                    styleChips()
                }
                tag = c.id
            }
            chipRow.addView(chip, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginEnd = dp(8) })
        }
        styleChips()
        (chipRow.parent as HorizontalScrollView).scrollTo(0, 0)
    }

    private fun styleChips() {
        val accent = getColor(if (type == TYPE_EXPENSE) R.color.arnic_expense else R.color.arnic_income)
        for (i in 0 until chipRow.childCount) {
            val chip = chipRow.getChildAt(i) as TextView
            val selected = chip.tag == categoryId
            chip.background = rounded(if (selected) withAlpha(accent, 0.20f) else getColor(R.color.arnic_key), 14f, if (selected) accent else Color.TRANSPARENT)
            chip.setTextColor(getColor(if (selected) R.color.arnic_on_surface else R.color.arnic_on_surface_variant))
        }
    }

    private fun buildKeypad() {
        val grid = findViewById<GridLayout>(R.id.quick_keypad)
        grid.removeAllViews()
        for (key in listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫")) {
            val k = TextView(this).apply {
                text = key
                textSize = 26f
                gravity = Gravity.CENTER
                setTextColor(getColor(R.color.arnic_on_surface))
                background = rounded(getColor(if (key == "⌫") R.color.arnic_key_alt else R.color.arnic_key), 16f)
                contentDescription = when (key) { "⌫" -> getString(R.string.quick_delete); "." -> getString(R.string.quick_decimal); else -> key }
                setOnClickListener {
                    amount = QuickDb.applyKey(amount, key)
                    renderAmount()
                }
            }
            val lp = GridLayout.LayoutParams(GridLayout.spec(GridLayout.UNDEFINED, 1f), GridLayout.spec(GridLayout.UNDEFINED, 1f)).apply {
                width = 0; height = dp(56); setMargins(dp(3), dp(3), dp(3), dp(3))
            }
            grid.addView(k, lp)
        }
    }

    private fun renderAmount() {
        amountView.text = if (amount.isEmpty()) "0" else QuickDb.groupForDisplay(amount)
        amountView.alpha = if (amount.isEmpty()) 0.3f else 1f
        findViewById<TextView>(R.id.quick_currency).text = currency
    }

    private fun save() {
        val database = db ?: return
        val minor = QuickDb.parseMinor(amount)
        if (minor <= 0) {
            haptic(long = true)
            Toast.makeText(this, R.string.quick_enter_amount, Toast.LENGTH_SHORT).show()
            return
        }
        val cat = categoryId
        val acc = accountId
        if (cat == null || acc == null) {
            Toast.makeText(this, R.string.quick_open_app_first, Toast.LENGTH_LONG).show()
            return
        }
        try {
            QuickDb.insertTransaction(database, type, minor, cat, acc)
        } catch (e: Exception) {
            Toast.makeText(this, R.string.quick_save_failed, Toast.LENGTH_LONG).show()
            return
        }
        haptic(long = false)
        val name = categories.firstOrNull { it.id == cat }?.name.orEmpty()
        val label = getString(if (type == TYPE_EXPENSE) R.string.quick_saved_expense else R.string.quick_saved_income)
        Toast.makeText(this, "$label · ${QuickDb.formatMoney(minor, currency)} · $name", Toast.LENGTH_SHORT).show()
        // Un aviso fallido no debe impedir que el movimiento ya guardado se vea.
        try {
            BudgetAlertChecker.checkAndNotify(this, database, currency)
        } catch (e: Exception) {
            // ignorado a propósito
        }
        QuickWidgetProvider.refreshAll(this)
        finishAndRemoveTask()
    }

    private fun showMessage(text: String, openApp: Boolean) {
        findViewById<View>(R.id.quick_entry_group).visibility = View.GONE
        findViewById<TextView>(R.id.quick_message).apply {
            this.text = text
            visibility = View.VISIBLE
        }
        saveButton.apply {
            visibility = View.VISIBLE
            this.text = getString(R.string.quick_open_app)
            background = rounded(getColor(R.color.arnic_brand), 18f)
            setTextColor(Color.WHITE)
            setOnClickListener {
                if (openApp) startActivity(Intent(this@QuickEntryActivity, MainActivity::class.java))
                finishAndRemoveTask()
            }
        }
    }

    // ── Utilidades de estilo ────────────────────────────────────────────────────

    private fun styleToggle(b: Button, selected: Boolean, color: Int) {
        b.background = rounded(if (selected) withAlpha(color, 0.18f) else getColor(R.color.arnic_key), 16f, if (selected) color else Color.TRANSPARENT)
        b.setTextColor(if (selected) color else getColor(R.color.arnic_on_surface_variant))
    }

    private fun rounded(fill: Int, radiusDp: Float, stroke: Int = Color.TRANSPARENT) = GradientDrawable().apply {
        setColor(fill)
        cornerRadius = dp(radiusDp.toInt()).toFloat()
        if (stroke != Color.TRANSPARENT) setStroke(dp(2), stroke)
    }

    private fun withAlpha(color: Int, alpha: Float) = Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    @Suppress("DEPRECATION")
    private fun haptic(long: Boolean) {
        if (Build.VERSION.SDK_INT >= 30) {
            sheet.performHapticFeedback(if (long) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.CONFIRM)
        } else {
            val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            v?.vibrate(VibrationEffect.createOneShot(if (long) 60 else 20, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }

    companion object {
        const val EXTRA_TYPE = "type"
        const val TYPE_EXPENSE = "expense"
        const val TYPE_INCOME = "income"

        private fun normalizeType(t: String?) = if (t == TYPE_INCOME) TYPE_INCOME else TYPE_EXPENSE

        fun intent(context: Context, type: String): Intent =
            Intent(context, QuickEntryActivity::class.java)
                .putExtra(EXTRA_TYPE, type)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
