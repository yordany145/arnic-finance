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
- **Sincronización** (ya implementada, opcional): ids UUID, `updated_at`, borrado lógico (`deleted_at`) — se
  pensaron desde el principio para esto. Ver "Integración externa" más abajo.
- **Privacidad**: todo local por defecto; el manifest de release no pide `INTERNET`. El envío de datos al
  servidor opcional es opt-in explícito (Ajustes > Integraciones, apagado por defecto).
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

## Bloqueo de la app

`platform/app_lock.dart` (`local_auth`, biometría o PIN/patrón del sistema) + `data/app_lock_prefs.dart`
(preferencia en `shared_preferences`, no en `app_settings` de drift: es sólo de este dispositivo). Android
exige `FlutterFragmentActivity` en vez de `FlutterActivity` (ver `MainActivity.kt`) y un `LaunchTheme` con
padre `Theme.AppCompat` (ver `android/app/src/main/res/values*/styles.xml`).

## Asistente (`domain/assistant/`)

Motor de intención + slots en español (no un LLM): `text_normalize.dart` (typos vía Levenshtein con
transposición), `period_parser.dart`, `amount_parser.dart`, `intent_parser.dart` (clasifica, con reglas
ordenadas por especificidad — ver sus propios comentarios antes de reordenar nada) y `assistant_engine.dart`
(responde consultando los mismos repositorios que el resto de la app). Hallazgo central: una alerta
personalizada pedida en el chat ("avísame si gasto más de X en Y") se implementa creando/actualizando un
`Budget` real vía `BudgetRepository`, no un motor de reglas paralelo.

## Respaldo (`data/backup_service.dart`)

Exporta/restaura cuentas, categorías, movimientos, presupuestos y ajustes como un único JSON, usando los
`toJson()`/`fromJson()` que drift ya genera por tabla. Restaurar reemplaza todo (no combina) dentro de una
transacción, respetando el orden de claves foráneas al borrar e insertar.

## Integración externa (`server/`, opcional)

Paquete Dart aparte (sin Flutter) con su propia copia documentada del esquema (`server/lib/db/tables.dart`,
mismo contrato que `lib/data/tables.dart`/Kotlin/Swift: no cambiar un lado sin el otro). Expone una API HTTP
(`docs/API.md`) para que un servicio externo (p. ej. el puente de correo `bridge/`) registre o lea movimientos.

- **Por qué un servidor aparte y no una librería compartida**: el paquete principal depende de Flutter; un
  paquete Dart puro no puede importarlo sin arrastrar el SDK de Flutter a un servidor. Se optó por el mismo
  patrón de "contrato documentado, código duplicado a propósito" que ya usan `QuickDb.kt`/`QuickDb.swift`.
- **Un solo teléfono por cuenta**: la sincronización (`GET`/`POST /v1/sync`, `data/server_sync_service.dart`
  del lado Flutter) compara `updated_at` contra el último cursor — no hay que resolver conflictos entre
  varios dispositivos porque, a propósito, no los hay.
- **Auth**: una API key de 256 bits por cuenta (su hash SHA-256 es lo único que se guarda), aprovisionada
  una vez con `POST /v1/setup` protegido por `SETUP_TOKEN` (variable de entorno, nunca viaja a la app salvo
  en ese primer intercambio).
- **Apagado por defecto**: `ServerSyncPrefs.enabled` controla si `syncWithServerIfEnabled` (en `state/providers.dart`,
  llamado junto a `checkBudgetAlerts` en los mismos puntos) hace algo o no. Mientras esté en `false`, la app
  no hace ninguna llamada de red — la promesa de "100% local" se mantiene literalmente.
