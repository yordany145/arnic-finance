# Arquitectura

```
lib/
  core/        formato de dinero, teclado numérico (reglas), fechas, tema, emojis
  domain/      modelos, enums, DateRange, contratos de repositorio (interfaces)
  data/        drift (SQLite): tablas, migraciones, semillas, repositorios drift
  state/       Riverpod: providers y filtro del historial
  navigation/  go_router
  platform/    puente con lo nativo (MethodChannel com.arnic.finance/quick)
  ui/          screens/ y widgets/
android/app/src/main/kotlin/com/arnic/finance/
  MainActivity.kt          canal: añadir tile / anclar widget / refrescar widget
  quick/QuickEntryActivity hoja de registro rápido (Views, sin Flutter)
  quick/QuickTileService   tiles Gasto e Ingreso
  quick/QuickWidgetProvider widget de inicio
  quick/QuickDb            SQLite compartido con Dart (contrato)
ios/ArnicQuick/            Swift sin compilar (intents, controles, widget)
```

## Decisiones
- **Flutter** (una base de código para la app completa) + **nativo sólo para lo que el SO exige**:
  las hojas/controles del sistema no pueden ser Flutter de forma práctica ni rápida.
- **SQLite con drift**: tipado, streams reactivos, migraciones (`schemaVersion`), y el archivo es legible desde Kotlin/Swift.
- **Dinero en enteros** (`amount_minor`), nunca `double`.
- **Emojis como iconos** de categorías/cuentas: idénticos en Flutter, Kotlin y Swift sin mapear nombres.
- **Sincronización futura**: ids UUID, `updated_at`, borrado lógico (`deleted_at`), acceso vía interfaces
  (`domain/repositories.dart`). Bastará una implementación remota/decorador y un proveedor distinto en `state/providers.dart`.
  Cuentas de usuario: añadir `user_id` en una migración.
- **Privacidad**: todo local; el manifest de release no pide `INTERNET`. Cualquier envío futuro debe ser opt-in.
- **Contrato con lo nativo**: `lib/data/tables.dart` ↔ `QuickDb.kt` / `QuickDb.swift`. Al cambiar el esquema:
  subir `AppDatabase.kSchemaVersion`, actualizar ambos `SUPPORTED_SCHEMA`, y añadir migración.
  Los nativos se niegan a escribir si la versión no coincide (nunca corrompen datos).
- **Refresco**: el registro rápido escribe desde otro proceso; al volver a primer plano la app llama a
  `markTablesUpdated` para releer.

## Presupuestos y avisos (schemaVersion 2)

- `domain/budget.dart`: `Budget`, `BudgetProgress` (ratio, `level` 80%/100%), `monthPeriodKey`.
- Tablas nuevas: `budgets` (categoría/general/ahorro) y `budget_alerts` (qué avisos ya se mandaron,
  clave primaria `budgetId+periodKey+level` — así nunca se repite un aviso, ni entre reintentos ni
  entre procesos: Dart, Kotlin y Swift comparten la misma tabla).
- `DriftBudgetRepository.watchProgress`: progreso del mes en curso por presupuesto (stream).
- `BudgetAlertService.check`: recorre los presupuestos, y si alguno cruzó un nivel nuevo, notifica
  (`platform/notifications.dart`, `flutter_local_notifications`). Se llama tras guardar/editar/borrar/
  restaurar un movimiento y al reanudar la app (`checkBudgetAlerts` en `state/providers.dart`).
- **Android**: la hoja rápida nativa (`QuickEntryActivity`) hace el mismo chequeo en Kotlin
  (`quick/BudgetAlertChecker.kt`, mismo SQL que `DriftBudgetRepository`) y dispara la notificación del
  sistema directamente, sin pasar por Flutter. Necesita `POST_NOTIFICATIONS` (Android 13+), pedido la
  primera vez que el usuario crea un presupuesto (`BudgetsScreen` → `BudgetNotifier.requestPermission`).
- **iOS**: mismo patrón en `ios/ArnicQuick/Shared/BudgetAlertChecker.swift` (sin compilar, como el
  resto de iOS), llamado desde `RecordMovementIntent.perform()`.
- Al subir el esquema: además de `QuickDb.SUPPORTED_SCHEMA`/`supportedSchema`, revisa si el nuevo dato
  também lo necesita `BudgetAlertChecker` en los tres lenguajes.
