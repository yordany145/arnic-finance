import AppIntents
import SwiftUI
import WidgetKit

// ⚠️ SIN COMPILAR: escrito en Linux (sin Xcode). Ver docs/IOS.md.
// Target: extensión "ArnicWidgets" (Widget Extension). Incluir también Shared/QuickDb.swift
// y Shared/QuickIntents.swift en este target.

@main
struct ArnicWidgets: WidgetBundle {
    var body: some Widget {
        ArnicQuickWidget()
        if #available(iOS 18.0, *) {
            ArnicExpenseControl()
            ArnicIncomeControl()
        }
    }
}

// MARK: - Controles (Centro de control, pantalla de bloqueo, botón de acción) · iOS 18+

@available(iOS 18.0, *)
struct ArnicExpenseControl: ControlWidget {
    static let kind = "com.arnic.finance.control.expense"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenQuickAddIntent(kind: .expense)) {
                Label("Gasto", systemImage: "minus.circle.fill")
            }
        }
        .displayName("Registrar gasto")
        .description("Abre Arnic Finance directo en el registro de un gasto.")
    }
}

@available(iOS 18.0, *)
struct ArnicIncomeControl: ControlWidget {
    static let kind = "com.arnic.finance.control.income"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenQuickAddIntent(kind: .income)) {
                Label("Ingreso", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Registrar ingreso")
        .description("Abre Arnic Finance directo en el registro de un ingreso.")
    }
}

// MARK: - Widget de pantalla de inicio (iOS 17+)
// Los widgets de iOS no admiten campos de texto: los botones abren la app en el registro.

struct QuickEntry: TimelineEntry {
    let date: Date
    let summary: String
}

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now, summary: "Hoy: RD$0") }

    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> QuickEntry {
        let summary = (try? QuickDb.withDatabase { db in
            "Hoy: \(QuickDb.formatMoney(QuickDb.todayExpenseMinor(db), symbol: QuickDb.currencySymbol(db)))"
        }) ?? "Abre Arnic Finance"
        return QuickEntry(date: .now, summary: summary)
    }
}

struct ArnicQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.arnic.finance.widget.quick", provider: QuickProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.summary).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
                HStack(spacing: 8) {
                    Link(destination: URL(string: "arnic:///add?type=expense")!) { pill("− Gasto", .red) }
                    Link(destination: URL(string: "arnic:///add?type=income")!) { pill("+ Ingreso", .green) }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Arnic Finance")
        .description("Total de gastos de hoy y acceso directo al registro.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    private func pill(_ title: String, _ color: Color) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(color)
    }
}
