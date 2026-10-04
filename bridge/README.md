# Puente Arnic Finance (correo del banco → app → Telegram)

Lee los avisos de consumo de la tarjeta en un Gmail, los registra en Arnic Finance,
avisa por Telegram al llegar al 80% y 100% de un presupuesto y manda reportes diario (9 PM)
y semanal (domingo 8 PM). Solo librería estándar de Python, sin instalar nada.

## Puesta en marcha (3 pasos)
1. `python3 setup.py` — pide URL, API key (Ajustes > Integraciones > Ver API key), el Gmail de la tarjeta,
   su contraseña de aplicación (myaccount.google.com/apppasswords, requiere verificación en 2 pasos)
   y el correo del banco. Guarda todo con permisos 600 y prueba las conexiones.
2. `python3 -m arnic_bridge ingest --dry-run` — muestra qué registraría, sin tocar nada.
3. `deploy/install.sh` — activa la revisión cada 5 min y los reportes.

## Comandos
- `ingest [--dry-run] [--file aviso.eml]` · `report daily|weekly` · `check`
- Pruebas: `python3 -m unittest discover -s tests`

## Notas
- Los gastos USD no se registran hasta definir `usd_to_local` en `config.local.json` (avisa por Telegram).
- Rechazos, reversos y publicidad se ignoran. Un correo nunca se registra dos veces (`state.db`).
- El parser es genérico: al llegar un aviso real del banco, se añade a `tests/test_bridge.py` y se ajusta `parser.py`.
- Los presupuestos y gastos se leen del espejo del servidor (Render): los presupuestos cambian ahí
  cuando la app sincroniza; el teléfono sigue siendo la fuente de verdad.


## Qué hace además de registrar consumos

- **Sueldo.** Un depósito en Qik desde Banreservas por ~30,000 (±10 %, configurable en `salary`) se registra como ingreso
  "Salario" en "Qik ahorros". La descripción que se escribe en la transferencia ("sueldo", "nómina") **no llega en ningún
  correo** (el recibo de Banreservas trae el campo sin rellenar y Qik no la incluye), por eso se reconoce por banco de origen
  + monto. Cualquier otro depósito o transferencia se ignora.
- **Tarjetas por ciclo.** Límite, día de corte y día de pago se editan en la app (Ajustes > Tarjetas de crédito), se guardan en
  el servidor (`/v1/config`) y de ahí los lee el puente. El consumo se mide por ciclo de facturación y no descuenta pagos.
  Avisos al 80 % y 100 % del límite, y recordatorio de pago 3 días antes, el día anterior y el mismo día (en el reporte de las 21:00).
- **Consumo inusual.** Cada aviso de compra añade "🔎 Consumo inusual" si el comercio es del extranjero, el monto es muy alto
  frente a lo habitual o es un comercio nuevo con monto relevante (umbrales en `unusual`).
- **Categorías que aprenden.** Si cambias la categoría de un consumo en la app, el puente recuerda ese comercio.
- **Suscripciones.** Detecta cobros mensuales recurrentes y los lista en los reportes (`subscriptions --mail-days 180` para
  buscarlos también en el correo).
- **Metas de ahorro.** `goals` en la config: `[{"name": "Fondo", "account": "Qik ahorros", "target": 100000}]`.

## Comandos de consulta (los usa JARVIS por Telegram)

```bash
python3 -m arnic_bridge summary --period today|week|month|all [--category Comida] [--account "Tarjeta BHD"]
python3 -m arnic_bridge cards
python3 -m arnic_bridge add-expense 500 Comida --note "Almuerzo" [--account Efectivo]
python3 -m arnic_bridge add-income 1000 Otros --note "Venta"
python3 -m arnic_bridge report daily|weekly|monthly [--month 2026-10] [--print]
```

El reporte mensual llega por Telegram como Excel (`.xlsx`) el día 1 a las 8:00 (hoja Resumen, Movimientos y Suscripciones).
