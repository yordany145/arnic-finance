import AppIntents
import Foundation

// ⚠️ SIN COMPILAR: escrito en Linux (sin Xcode). Ver docs/IOS.md.
// Target membership: Runner (App Intents/Atajos/Siri) y ArnicWidgets (para OpenQuickAddIntent).

enum MovementKind: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tipo"
    static let caseDisplayRepresentations: [MovementKind: DisplayRepresentation] = [
        .expense: "Gasto",
        .income: "Ingreso",
    ]
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría"
    static let defaultQuery = CategoryQuery()

    var id: String
    var name: String
    var icon: String
    var type: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(icon) \(name)")
    }

    init(_ c: QuickDb.Category) {
        id = c.id; name = c.name; icon = c.icon; type = c.type
    }
}

struct CategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        try QuickDb.withDatabase { db in try QuickDb.categories(db) }
            .filter { identifiers.contains($0.id) }
            .map(CategoryEntity.init)
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        try QuickDb.withDatabase { db in try QuickDb.categories(db) }.map(CategoryEntity.init)
    }
}

/// Registra un movimiento SIN abrir la app: se ejecuta en segundo plano desde Siri,
/// Atajos, Spotlight o el botón de acción (asignándole un Atajo). Escribe directo
/// en el SQLite del App Group.
struct RecordMovementIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar gasto o ingreso"
    static let description = IntentDescription("Guarda un gasto o ingreso en Arnic Finance sin abrir la app.")

    @Parameter(title: "Tipo", default: .expense)
    var kind: MovementKind

    @Parameter(title: "Monto", requestValueDialog: "¿Cuánto?")
    var amount: Double

    @Parameter(title: "Categoría")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$kind) de \(\.$amount) en \(\.$category)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let minor = Int64((amount * 100).rounded())
        guard minor > 0 else { throw $amount.needsValueError("Escribe un monto mayor que cero") }

        let message: String
        do {
            message = try QuickDb.withDatabase { db in
                let cats = try QuickDb.categories(db, type: kind.rawValue)
                // Si no se eligió categoría (o no corresponde al tipo): la más usada.
                let chosen = cats.first { $0.id == category?.id } ?? cats.first
                guard let chosen, let account = try QuickDb.defaultAccountId(db) else { throw QuickDb.DbError.missing }
                try QuickDb.insertTransaction(db, type: kind.rawValue, amountMinor: minor, categoryId: chosen.id, accountId: account)
                let symbol = QuickDb.currencySymbol(db)
                BudgetAlertChecker.checkAndNotify(db, currency: symbol)
                return "\(kind == .expense ? "Gasto" : "Ingreso") guardado · \(QuickDb.formatMoney(minor, symbol: symbol)) · \(chosen.name)"
            }
        } catch QuickDb.DbError.missing {
            return .result(dialog: "Abre Arnic Finance una vez para preparar tus categorías.")
        } catch QuickDb.DbError.appTooOld {
            return .result(dialog: "Actualiza Arnic Finance: tus datos son de una versión más nueva.")
        }
        return .result(dialog: "\(message)")
    }
}

struct ArnicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordMovementIntent(),
            phrases: [
                "Registrar un gasto en \(.applicationName)",
                "Registrar un movimiento en \(.applicationName)",
            ],
            shortTitle: "Registrar",
            systemImageName: "plus.circle.fill"
        )
    }
}

/// Para los controles y widgets: abre la app directo en la pantalla de registro.
/// (Un control de iOS no puede mostrar un teclado; ver docs/SISTEMA_ANDROID_IOS.md.)
/// La ruta queda en el App Group y la app la recoge al abrirse (AppDelegate → Dart).
struct OpenQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir registro rápido"
    static let openAppWhenRun = true

    @Parameter(title: "Tipo", default: .expense)
    var kind: MovementKind

    init() {}
    init(kind: MovementKind) { self.kind = kind }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: QuickDb.appGroup)?.set("/add?type=\(kind.rawValue)", forKey: QuickDb.pendingRouteKey)
        return .result()
    }
}
