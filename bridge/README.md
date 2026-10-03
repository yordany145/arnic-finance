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
