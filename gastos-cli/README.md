# gastos

Gestor de gastos personales desde la terminal. Sin dependencias externas: solo Python y SQLite.

- Registra gastos por categoría.
- Resumen mensual con presupuestos y aviso cuando te pasas.
- Compara cada categoría con el mes anterior.
- Exporta e importa CSV para usarlo con Excel o Google Sheets.

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
gastos editar 3 --importe 15 --descripcion "cena"
gastos borrar 3
gastos exportar > gastos.csv
gastos importar gastos.csv
```

Ejemplo de `gastos resumen`:

```
Resumen de 2026-10 (comparado con 2026-09)
  comida             125,00 €  de 200,00 € (62%)  | +25,00 € (+25%)
  ocio                30,00 €  | -10,00 € (-25%)
  libros               8,00 €  | nuevo
  TOTAL              163,00 €  | +23,00 € (+16%)
```

`editar` solo cambia los campos que indiques. `importar` lee el mismo formato que genera
`exportar` (la columna `id` se ignora y se crean gastos nuevos). Si alguna línea tiene un error,
no se importa nada y se indica qué línea falla.

Los datos se guardan en `~/.gastos.db`. Puedes cambiar la ruta con `--db` o con la variable
de entorno `GASTOS_DB`.

## Desarrollo

```bash
python -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/pytest -q
.venv/bin/ruff check .
```

El fichero `.gitlab-ci.yml` ejecuta los tests y el linter en cada push a GitLab.
