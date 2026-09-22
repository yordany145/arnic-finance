# iOS: puesta en marcha (requiere un Mac con Xcode 16+)

Todo el código Swift está escrito pero **no se ha compilado nunca** (se desarrolló en Linux).
Espera pequeños ajustes de compilación. Lo que el proyecto Flutter ya trae hecho:
`ios/Runner/AppDelegate.swift` (canal `consumePendingRoute`) y esquema URL `arnic://` en `Info.plist`.

## Pasos

1. `flutter pub get && cd ios && pod install` y abre `ios/Runner.xcworkspace`.
2. **Deployment target**: sube Runner a **iOS 17.0** (los controles necesitan iOS 18 en el dispositivo, con `#available`).
3. **App Group**: en *Signing & Capabilities* de Runner → `+ Capability` → *App Groups* → `group.com.arnic.finance`.
   (Si usas otro id, cámbialo en `lib/data/db_location.dart` → `kAppGroupId`, `QuickDb.swift`, `AppDelegate.swift`.)
4. **Extensión**: *File → New → Target → Widget Extension* llamada `ArnicWidgets` (sin Live Activity ni Configuration Intent).
   Bórrale los archivos de plantilla y añade `ios/ArnicQuick/Widgets/ArnicWidgets.swift`. Activa también *App Groups* en ese target con el mismo id.
5. **Target membership**:
   - `Shared/QuickDb.swift` → Runner **y** ArnicWidgets.
   - `Shared/QuickIntents.swift` → Runner **y** ArnicWidgets.
6. Compila y ejecuta en un iPhone. **Abre la app una vez** (crea la base y las categorías) antes de probar los accesos.
7. Añade el control: Centro de control → editar → *Añadir control* → Arnic. En Ajustes → Botón de acción puedes asignar un Atajo con "Registrar gasto o ingreso".

## Si algo falla
- "Abre Arnic Finance una vez…": el App Group no coincide o la app aún no creó la base.
- El control no aparece: requiere iOS 18 y la extensión firmada con el mismo equipo.
- Los datos se guardan en el contenedor del App Group **desde la primera ejecución**; configúralo antes de usar la app con datos reales (si no, se usaría el directorio privado y luego no se moverían solos).
