# Arnic Finance — servidor opcional para integraciones

Paquete Dart independiente (sin Flutter). Expone una API HTTP para que
servicios externos (p. ej. un servicio externo) puedan leer y registrar
movimientos, sincronizándose con la app del teléfono.

**No hace falta esto para usar Arnic Finance normalmente** — sólo si vas a
activar "Sincronizar con el servidor" en Ajustes. Ver `docs/API.md` en la raíz del
repo para la guía completa (despliegue en Render, cómo conectarlo a la app,
referencia de cada endpoint).

## Desarrollo local

```bash
dart pub get
dart run build_runner build   # genera lib/db/database.g.dart
SETUP_TOKEN=prueba dart run bin/server.dart
dart test
```

## Estructura

```
lib/
  db/tables.dart       esquema (copia documentada del contrato con ../../lib/data/tables.dart)
  db/database.dart      base de datos drift (SQLite, sin Flutter)
  util/                 auth, rate limit, parseo de categorías/montos, períodos
  routes/                un archivo por grupo de endpoints
  auth_middleware.dart   exige Authorization: Bearer <api_key>
  server.dart            arma el Handler completo
bin/server.dart          entrypoint (lee PORT/SETUP_TOKEN/DB_PATH de env)
Dockerfile               build multi-stage, pensado para Render/Cloud Run
```
