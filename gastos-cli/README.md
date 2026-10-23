# gastos

Gestor de gastos personales desde la terminal. Sin dependencias externas: solo Python y SQLite.

- Registra gastos por categoría.
- Resumen mensual con presupuestos y aviso cuando te pasas.
- Exporta a CSV para abrirlo en Excel o Google Sheets.

## Instalación

```bash
pip install .
```

## Uso

```bash
gastos anadir 12,50 comida "menú del día"
gastos anadir 2 transporte --fecha 2026-10-01
gastos presupuesto comida 200
gastos listar --mes 2026-10
gastos resumen                 # mes actual
gastos borrar 3
gastos exportar > gastos.csv
```

Ejemplo de `gastos resumen`:

```
Resumen de 2026-10
  comida             12,50 €  de 200,00 € (6%)
  transporte          2,00 €
  TOTAL              14,50 €
```

Los datos se guardan en `~/.gastos.db`. Puedes cambiar la ruta con `--db` o con la variable
de entorno `GASTOS_DB`.

## Desarrollo

```bash
python -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/pytest -q
.venv/bin/ruff check .
```

El fichero `.gitlab-ci.yml` ejecuta los tests y el linter en cada push a GitLab.
