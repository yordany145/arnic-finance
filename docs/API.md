# API para integraciones externas

Esta API es **opcional** y vive en `server/` — un paquete Dart aparte, sin
Flutter. Si nunca la despliegas y nunca activas "Sincronizar con el servidor" en
Ajustes, la app sigue siendo 100% local, igual que siempre.

## Por qué existe un servidor, si la app es local

La base de datos real de Arnic Finance vive sólo en tu teléfono. Para que
un servicio externo (como el puente de correo `bridge/`) pueda "ver" o "registrar" un
gasto, algo tiene que estar accesible por internet — un teléfono detrás de
NAT del operador no lo está. Este servidor es un **espejo mínimo**: guarda una
copia de tus cuentas/categorías/movimientos/presupuestos y se sincroniza con
el teléfono. **El teléfono sigue siendo la fuente de verdad**: si el espejo
del servidor se pierde (ver la nota sobre Render más abajo), basta con
"Forzar sincronización completa" en la app para reconstruirlo.

## 1. Desplegar el servidor (gratis, sin tarjeta)

[Render](https://render.com) tiene un plan gratuito real: sin tarjeta de
crédito, con soporte para Docker, 750 horas/mes. Única concesión: si nadie lo
usa en 15 minutos se "duerme" y la primera llamada después tarda ~1 minuto en
responder — razonable para un servicio que se consulta de vez en cuando.

1. Sube este repo a GitHub (o el que ya tienes).
2. En Render: **New > Web Service**, conecta el repo, y en "Root Directory"
   pon `server`. Render detecta el `Dockerfile` solo.
3. Variables de entorno (pestaña **Environment**):
   - `SETUP_TOKEN` — invéntate un secreto largo (ej. `openssl rand -hex 32`
     en tu PC). Lo necesitas una sola vez para aprovisionar la API key.
   - `DB_PATH` — déjalo en el valor por defecto (`arnic_server.db`) a menos
     que configures un disco persistente (plan pago de Render). **En el plan
     gratis, el archivo se borra en cada redeploy** — no es grave: la próxima
     sincronización completa desde el teléfono lo reconstruye.
4. Despliega. Cuando esté arriba, anota la URL pública (algo como
   `https://arnic-finance-xxxx.onrender.com`).

### Probarlo localmente primero (opcional)

```bash
cd server
dart pub get
SETUP_TOKEN=prueba123 dart run bin/server.dart
# en otra terminal:
curl -X POST -H "x-setup-token: prueba123" http://localhost:8080/v1/setup
```

## 2. Conectar la app al servidor

En la app: **Ajustes > Integraciones > Configurar servidor**. Pega la URL de
Render y el `SETUP_TOKEN` que elegiste. La app llama a `POST /v1/setup` por
ti, recibe una **API key** (256 bits, se guarda sólo en este teléfono) y hace
una primera sincronización completa. El setup token NO se guarda en la app:
sólo sirve para ese primer intercambio.

Si pierdes el teléfono o quieres invalidar la key, usa "Regenerar API key"
(necesitas el `SETUP_TOKEN` de nuevo) o bórrala directamente del servidor.

## 3. Conectar un servicio externo

Con el servidor arriba y la app sincronizada al menos una vez, ya tienes lo que
cualquier servicio necesita: una URL base y una API key Bearer. El primero en
usarlo es el puente de correo de este repo (`bridge/`, ver su README): lee los
avisos de consumo de tus tarjetas y los registra con estos endpoints:

- `POST {url}/v1/movements` — registrar un gasto/ingreso.
- `GET {url}/v1/summary?period=today|week|month|all` — ver totales.
- `GET {url}/v1/categories` / `GET {url}/v1/accounts` — resolver nombres antes de registrar.

Cualquier otro programa tuyo puede usarlos igual.

## Persistencia: que la API key y los datos sobrevivan a un reinicio

El plan gratis de Render tiene disco efímero: al desplegar o recrear el contenedor, la base de datos se pierde, y con ella
la API key. Dos mecanismos lo hacen indoloro (el teléfono sigue siendo la fuente de verdad):

- **`API_KEY_HASH`** (variable de entorno, opcional). Es el SHA-256 de tu API key
  (`printf '%s' "$TU_KEY" | sha256sum`). Si la base está vacía, el servidor crea el usuario con esa clave al arrancar, así que
  la misma key sigue valiendo tras un reinicio. Solo se guarda el hash, igual que con una key generada. Si regeneras la key
  (`rotate`), actualiza esta variable.
- **`epoch`** en `GET /v1/sync`: un identificador aleatorio creado con la base. Si cambia, la app entiende que el servidor
  perdió sus datos y vuelve a subir todo sola, una sola vez.

Con las dos, un reinicio no pide generar ni copiar nada: al abrir la app, el servidor se repone.

## Referencia de la API

Todas las rutas bajo `/v1/` (salvo `/v1/setup`) requieren:

```
Authorization: Bearer <tu_api_key>
```

### `POST /v1/setup`

Aprovisiona o rota la única API key del servidor. Protegido por
`X-Setup-Token` (no por API key, porque la primera vez no existe ninguna).

```jsonc
// Headers: X-Setup-Token: <SETUP_TOKEN>
// Body (opcional):
{"rotate": false}

// 201 (primera vez) / 200 (rotate: true):
{"userId": "...", "apiKey": "..."}
// 409 si ya existe una key y no mandaste rotate:true.
```

### `POST /v1/movements`

```jsonc
{
  "type": "expense",           // "expense" | "income"
  "amount": 500.00,            // o "amountMinor": 50000 (centavos) — uno de los dos
  "category": "Comida",        // nombre (con o sin acentos/mayúsculas) o id
  "account": "Efectivo",       // opcional: si se omite, usa la cuenta predeterminada
  "note": "Almuerzo",          // opcional
  "occurredAtMs": 1234567890   // opcional: epoch-ms, por defecto ahora
}
```

- `201` con el movimiento creado.
- `400` si falta el monto o el type no es válido.
- `422` con `{"suggestions": [...]}` si la categoría/cuenta no se reconoce —
  **nunca inventa una categoría nueva**: mejor reintentar con el nombre
  correcto.
- `409` si todavía no se sincronizó ninguna categoría/cuenta desde el
  teléfono (abre la app con la integración activada al menos una vez).

### `GET /v1/movements?type=&period=&limit=`

`period`: `today | yesterday | week | month | all` (por defecto `all`).
`limit`: 1-100 (por defecto 20). Devuelve los más recientes primero.

### `GET /v1/summary?period=`

```json
{"period": "month", "incomeMinor": 200000, "expenseMinor": 30000, "balanceMinor": 170000}
```

### `GET /v1/categories?type=expense|income` y `GET /v1/accounts`

Listan `{id, name, icon, type|kind}` — úsalos para resolver nombres antes de
llamar a `/v1/movements`, o para que un servicio pueda
mostrarte las opciones.

### `GET /v1/config` y `PUT /v1/config`

Configuración que edita la app y lee el puente de correo: límite y días de corte y de pago de cada tarjeta.

```jsonc
// GET → 200
{"updatedAt": 1790000000000, "config": {"cards": [{"accountId": "...", "limitMinor": 1500000, "cutDay": 15, "dueDay": 5}]}}

// PUT  {"config": {...}, "updatedAt": <hora de la edición en ms>}
// 200 {"updatedAt": ...} · 409 si el servidor ya tiene una edición más reciente · 400 si no valida
```

`cutDay`/`dueDay` son `null` o 1–31; `limitMinor` es un entero ≥ 0 en centavos. Gana la edición más reciente.

### `GET /v1/sync?since=<epochMs>` y `POST /v1/sync`

Las usa la app para sincronizarse; no hace falta llamarlas a mano salvo que
estés depurando. Ver `server/lib/routes/sync_routes.dart` para el formato
exacto de cada fila (es el mismo `toJson()` que ya genera drift, sin
`userId`).

## Seguridad, en corto

- La API key son 256 bits aleatorios; sólo se guarda su hash SHA-256 en el
  servidor (nunca el texto plano).
- `SETUP_TOKEN` protege el aprovisionamiento; guárdalo como el secreto que es
  (no lo subas a git, no lo compartas).
- Rate limiting básico por IP en todas las rutas (más estricto en `/v1/setup`).
- El servidor nunca confía en un `userId` que venga del cliente: siempre lo
  resuelve de la API key autenticada.
- Corre detrás de HTTPS (Render lo da gratis). No lo pongas detrás de HTTP
  plano en producción: la API key viajaría en claro.
