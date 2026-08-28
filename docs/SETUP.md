# SETUP — puesta en marcha

Estado: **sprint 1 parcial**. Lo que ya funciona no necesita credenciales de
Microsoft ni base de datos: puedes ejecutarlo ahora mismo.

---

## 1. Lo que ya puedes ejecutar hoy

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"

# Cadena completa sobre datos sintéticos:
# parseo → validación → cuarentena → informe de calidad → Project Health
.venv/bin/python -m app.cli demo

# Suite de tests
.venv/bin/python -m pytest -q

# Lint
.venv/bin/ruff check app tests
```

`app.cli demo` genera unos ficheros Excel deliberadamente sucios (cabecera en la
fila 7, fechas como texto, filas de subtotal, estados sin normalizar), los
procesa y muestra el Project Health con las evidencias de cada afirmación.

> Los datos de la demo son **sintéticos**. No corresponden a ningún proyecto
> real y no sirven para afirmar nada sobre proyectos reales (docs/05 §3.5).

## 2. Requisitos

| Software | Versión | Necesario para |
| --- | --- | --- |
| Python | 3.11+ | Backend y ML |
| Docker | reciente | PostgreSQL + pgvector (todavía no hace falta) |
| Node.js | 20 LTS o 22 | Frontend (todavía no existe) |

## 3. Base de datos (cuando llegue el sprint 1 completo)

```bash
docker compose -f infra/docker-compose.yml up -d db
cd backend && .venv/bin/alembic upgrade head
```

## 4. Configuración

```bash
cp .env.example .env
```

`.env` está en `.gitignore` y **nunca** se sube al repositorio.

Los valores de Microsoft los proporciona IT tras crear los dos App Registrations
(`docs/07-INSTALACION-IT-Y-DEV.md`). Hasta entonces, `LLM_PROVIDER=fake` y
`RETRIEVAL_PROVIDER=local` permiten trabajar sin ninguna credencial.

### Una comprobación que salta al arrancar

La configuración rechaza combinar `Sites.Selected` con `Files.Read.All` o
`Sites.Read.All`, porque el ámbito amplio anula el efecto restrictivo del
estrecho (`docs/04` §2). Es un fallo silencioso —todo seguiría funcionando, solo
que con acceso a todo el contenido del usuario— así que la aplicación no arranca
en esa configuración.

## 5. Estructura actual

```
backend/app/
├── config.py                  Configuración tipada + guardas de seguridad
├── cli.py                     Demostración ejecutable
├── schemas/domain.py          Modelo canónico (tareas, riesgos, recursos, presupuesto)
├── ingestion/
│   ├── excel/
│   │   ├── coercion.py        Conversión de valores; nunca adivina
│   │   ├── mapping.py         Contratos de datos desde YAML
│   │   ├── mappings/*.yaml    Adaptación a ficheros reales SIN tocar código
│   │   └── parser.py          Parseo con cuarentena y detección de fórmulas obsoletas
│   └── quality.py             Informe de calidad de datos
├── intelligence/
│   ├── evidence.py            Evidence Ledger
│   └── health/
│       ├── rules.yaml         Umbrales versionados
│       └── engine.py          Motor determinista de Project Health
├── observability/logging.py   Logs estructurados con redacción
└── dev/synthetic.py           DATOS SINTÉTICOS para la demo
```

## 6. Adaptar el sistema a vuestros Excel reales

No hay que tocar código. Se editan los alias en
`backend/app/ingestion/excel/mappings/*.yaml`:

```yaml
columns:
  planned_end:
    aliases: ["Planned End", "Fin Planificado", "Fecha Fin Prevista"]  # ← añadir aquí
    type: date
    required: true
```

Si el parser no encuentra la cabecera, el error dice exactamente qué columnas
obligatorias faltan y en qué fichero YAML añadirlas.

## 7. Qué falta para completar el sprint 1

- [ ] Modelos SQLAlchemy y migraciones de Alembic
- [ ] Validación de JWT de Entra ID y flujo On-Behalf-Of
- [ ] Endpoints de FastAPI y arranque de la aplicación
- [ ] Audit log persistido

Sprint 2 (Microsoft Graph) queda desbloqueado en cuanto IT entregue los
identificadores del App Registration.
