# Registro rápido desde el sistema: qué se puede y qué no

Investigado en la documentación oficial (developer.android.com, developer.apple.com) y comprobado
contra el `android.jar` de API 36 (`javap`). Estado real de cada pieza al final.

## Android

**Qué podemos hacer**
- Una **tile en el panel de ajustes rápidos** ("Arnic: Gasto" y "Arnic: Ingreso"): bajar el panel → pulsar → hoja de registro.
- Un **widget** de pantalla de inicio con el total gastado hoy y botones Gasto / Ingreso.
- **Atajos del icono** (mantener pulsado): "Registrar gasto" / "Registrar ingreso".
- Ofrecer la tile desde la app con un solo toque (`requestAddTileService`, Android 13+).

**Qué no podemos hacer**
- Meter un campo de texto **dentro** del widget: los `RemoteViews` sólo admiten toques y deslizamiento vertical. Los botones del widget abren la hoja rápida.
- Que la tile se añada sola sin que el usuario lo confirme: el sistema siempre muestra su diálogo.
- Mostrar la hoja con el teléfono bloqueado sin desbloquear (ver "Restricciones").
- `requestAddTileService` no existe antes de Android 13: allí el usuario la arrastra desde el editor del panel (lápiz).

| | |
|---|---|
| **API oficial** | `TileService` (+ `startActivityAndCollapse`), `AppWidgetProvider`/`RemoteViews`, shortcuts estáticos (`res/xml/shortcuts.xml`), `StatusBarManager.requestAddTileService`, `AppWidgetManager.requestPinAppWidget` |
| **Permisos** | **Ninguno de usuario.** `BIND_QUICK_SETTINGS_TILE` lo exige el sistema al *servicio* (se declara en el manifest, no se pide). La app ni siquiera declara `INTERNET` en release. |
| **Restricciones** | Etiqueta de tile ≤ 18 caracteres. Android 14+: `startActivityAndCollapse` sólo acepta `PendingIntent`. Bloqueado con PIN/huella: se usa `unlockAndRun` (se pide desbloquear antes). `showDialog()` de la tile no funciona con el dispositivo bloqueado; por eso se eligió una Activity. El widget se refresca al guardar y cada 30 min (mínimo de Android), así que el "hoy" puede tardar en reiniciarse tras medianoche. Si el fabricante oculta las tiles de terceros o el launcher no permite anclar widgets, hay ruta manual. |
| **Comportamiento** | Panel → **Arnic: Gasto** → (el panel se colapsa) hoja inferior con teclado numérico grande, chips de categoría y GUARDAR. La categoría más usada ya está elegida: para "RD$350 de comida" son **350 → Guardar**. Toast de confirmación y cierra sin dejar rastro en recientes. La app completa no se abre. |

**Por qué la hoja es nativa y no Flutter:** arrancar el motor de Flutter en frío cuesta cientos de ms;
una Activity de Views abre casi al instante. Leer/escribir el mismo SQLite desde Kotlin cuesta
~60 líneas y el contrato está documentado en `lib/data/tables.dart` y `QuickDb.kt`.

## iOS

**Qué podemos hacer**
- **Control de Centro de control / pantalla de bloqueo / botón de acción** (`ControlWidgetButton`, **iOS 18+**): un toque abre la app **directo en la pantalla de registro** (gasto o ingreso).
- **App Intent `RecordMovementIntent` + App Shortcuts** (iOS 16+): "Oye Siri, registrar un gasto en Arnic", Spotlight, Atajos o botón de acción vía un Atajo. **Registra sin abrir la app**, pidiendo el monto (`requestValue`) y opcionalmente la categoría.
- **Widget** de inicio con el total de hoy y enlaces al registro.

**Qué no podemos hacer (limitación real, no equivale a Android)**
- **Un control o widget de iOS no puede mostrar un teclado ni un campo de texto.** Un control es un botón que ejecuta un App Intent; los widgets interactivos (iOS 17) sólo admiten botones y toggles. Por eso **no existe "bajar el panel, teclear 350 y guardar" sin abrir nada**.
- Live Activities: sirven para eventos en curso (entrega, marcador); no son un atajo de entrada, así que **no se usan**.
- Los `SnippetIntent` (iOS 26) permiten una vista interactiva, pero sólo con botones/toggles: se podría simular un teclado con botones, pero sube mucho la complejidad; queda como mejora futura, no implementado.

**Lo más cercano a Android**
1. *Sin abrir la app:* Atajo/Siri/botón de acción con `RecordMovementIntent` (monto por voz o cuadro de diálogo del sistema → guarda).
2. *Rápido pero abriendo la app:* control de Centro de control → app en la pantalla de registro con teclado propio.

| | |
|---|---|
| **API oficial** | WidgetKit `ControlWidget`/`ControlWidgetButton` (iOS 18), App Intents `AppIntent`/`AppEntity`/`AppShortcutsProvider` (iOS 16), WidgetKit `StaticConfiguration` (iOS 17 para `containerBackground`) |
| **Permisos** | Ninguno de privacidad. **Sí**: capacidad **App Groups** (`group.com.arnic.finance`) en la app y en la extensión, para compartir el SQLite. Requiere firmar con un equipo de desarrollo de Apple. |
| **Restricciones** | Con el iPhone bloqueado, los controles que abren la app piden Face ID/código. Los Atajos pueden requerir desbloqueo según cómo se inicien. Si el App Group no está configurado, la app funciona pero los accesos rápidos no encuentran la base ("Abre Arnic Finance una vez…"). |
| **Comportamiento** | Control → app abierta en "Nuevo gasto" (teclado numérico propio, categoría más usada ya elegida). Siri/Atajo → diálogo "¿Cuánto?" → "Gasto guardado · RD$350 · Comida", sin abrir la app. |

## Estado de verificación (sé honesto con esto)

| Pieza | Estado |
|---|---|
| App Flutter (datos, UI, filtros) | ✅ Analiza sin errores; 21 tests (datos, fechas, teclado, flujo de UI) pasan |
| Android: tile, hoja rápida, widget, atajos | ✅ Compila y empaqueta APK release · ⚠️ **No probado en dispositivo/emulador** (ver README) |
| iOS: intents, controles, widget | ⚠️ **Escritos, NO compilados**: este equipo es Linux y no hay Xcode. Hay que añadir los targets en Xcode (docs/IOS.md) y probar en un iPhone con iOS 18 |
