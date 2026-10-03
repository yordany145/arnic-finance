# Arnic Finance

Finanzas personales, local y privada. Prioridad nº 1: **registrar un gasto o ingreso en segundos**,
incluso sin abrir la app.

- App completa (Flutter): balance, ingresos/gastos, historial con filtros (hoy, ayer, semana, mes, rango, todo),
  categorías editables con emoji, cuentas (Efectivo, Banco, Tarjeta…), moneda configurable (RD$ por defecto).
- **Android:** tiles del panel rápido, widget y atajos del icono → hoja nativa: *monto → Guardar*.
- **Presupuestos**: límites mensuales por categoría, un límite general de gasto y una meta de ahorro,
  con notificación al 80% y al 100% (desde la app, la hoja rápida de Android o el intent de iOS).
- **iOS:** control de Centro de control/botón de acción, App Intent/Siri/Atajos (registra sin abrir la app), widget.
  Ver la limitación de iOS en [docs/SISTEMA_ANDROID_IOS.md](docs/SISTEMA_ANDROID_IOS.md).
- **Bloqueo de la app**: huella/rostro/PIN del sistema al abrir y al volver de segundo plano (Ajustes > Seguridad).
- **Asistente**: chat local (no un LLM) que responde preguntas sobre tus finanzas y puede crear presupuestos
  a partir de una frase ("avísame si gasto más de 5000 en Comida"). Ver `lib/domain/assistant/`.
- **Respaldo**: exportar/restaurar todo el historial como un único JSON (Ajustes > Respaldo).
- **API opcional para integraciones** (p. ej. un conector de Meta IA): servidor aparte en `server/`,
  apagado por defecto — si no lo activas, la app sigue siendo 100% local. Ver [docs/API.md](docs/API.md).

## Entorno de este equipo
```bash
source ~/dev/env.sh   # Flutter 3.47.5, JDK 21, Android SDK (en ~/dev)
flutter pub get
dart run build_runner build   # regenera drift (lib/data/database.g.dart) si cambias tablas
flutter test
flutter run                   # con un móvil Android por USB o un emulador
flutter build apk --release --target-platform android-arm64
```

## Documentación
- [Qué se puede hacer en Android/iOS, permisos y restricciones](docs/SISTEMA_ANDROID_IOS.md)
- [Arquitectura y decisiones](docs/ARQUITECTURA.md)
- [Puesta en marcha de iOS (Xcode)](docs/IOS.md)
- [API opcional para integraciones externas (Meta IA, etc.)](docs/API.md)

## Próximos pasos sugeridos
1. Probar tile/widget en un teléfono real (no se ha podido en este equipo).
2. Compilar y probar iOS en un Mac.
3. Firma de release propia (ahora firma con la clave de depuración, sólo válido para instalar a mano).
4. Gráficos de reportes y movimientos recurrentes (el asistente ya cubre buena parte de "reportes" por chat).
5. Si se usa la API de integraciones en producción: disco persistente para el servidor (el plan gratis de
   Render es de almacenamiento efímero — ver docs/API.md) y, más adelante, soporte multi-dispositivo real
   si alguna vez hay más de un teléfono por cuenta.
