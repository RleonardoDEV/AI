"""Almacenamiento de gastos en SQLite (solo biblioteca estándar)."""

from __future__ import annotations

import os
import sqlite3
from dataclasses import dataclass
from datetime import date
from pathlib import Path

ESQUEMA = """
CREATE TABLE IF NOT EXISTS gastos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha       TEXT    NOT NULL,
    importe     INTEGER NOT NULL,  -- en céntimos, para evitar errores de redondeo
    categoria   TEXT    NOT NULL,
    descripcion TEXT    NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS presupuestos (
    categoria TEXT PRIMARY KEY,
    limite    INTEGER NOT NULL      -- límite mensual en céntimos
);
"""


@dataclass(frozen=True)
class Gasto:
    id: int
    fecha: date
    importe: int  # céntimos
    categoria: str
    descripcion: str


def ruta_por_defecto() -> Path:
    """Usa $GASTOS_DB si existe; si no, ~/.gastos.db."""
    return Path(os.environ.get("GASTOS_DB", Path.home() / ".gastos.db"))


class Almacen:
    def __init__(self, ruta: str | Path):
        self.con = sqlite3.connect(str(ruta))
        self.con.executescript(ESQUEMA)

    def cerrar(self) -> None:
        self.con.close()

    # --- gastos -----------------------------------------------------------
    def anadir(self, fecha: date, importe: int, categoria: str, descripcion: str = "") -> int:
        if importe <= 0:
            raise ValueError("El importe debe ser mayor que cero")
        cur = self.con.execute(
            "INSERT INTO gastos (fecha, importe, categoria, descripcion) VALUES (?, ?, ?, ?)",
            (fecha.isoformat(), importe, categoria.strip().lower(), descripcion.strip()),
        )
        self.con.commit()
        return int(cur.lastrowid)

    def editar(
        self,
        gasto_id: int,
        fecha: date | None = None,
        importe: int | None = None,
        categoria: str | None = None,
        descripcion: str | None = None,
    ) -> bool:
        """Cambia solo los campos indicados. Devuelve False si el gasto no existe."""
        if importe is not None and importe <= 0:
            raise ValueError("El importe debe ser mayor que cero")
        cambios: dict[str, object] = {}
        if fecha is not None:
            cambios["fecha"] = fecha.isoformat()
        if importe is not None:
            cambios["importe"] = importe
        if categoria is not None:
            cambios["categoria"] = categoria.strip().lower()
        if descripcion is not None:
            cambios["descripcion"] = descripcion.strip()
        if not cambios:
            existe = self.con.execute("SELECT 1 FROM gastos WHERE id = ?", (gasto_id,)).fetchone()
            return existe is not None
        columnas = ", ".join(f"{c} = ?" for c in cambios)  # nombres fijos, no vienen del usuario
        cur = self.con.execute(f"UPDATE gastos SET {columnas} WHERE id = ?", (*cambios.values(), gasto_id))
        self.con.commit()
        return cur.rowcount > 0

    def anadir_varios(self, gastos: list[tuple[date, int, str, str]]) -> int:
        """Inserta todos o ninguno. Devuelve cuántos se han insertado."""
        if any(importe <= 0 for _, importe, _, _ in gastos):
            raise ValueError("El importe debe ser mayor que cero")
        with self.con:
            self.con.executemany(
                "INSERT INTO gastos (fecha, importe, categoria, descripcion) VALUES (?, ?, ?, ?)",
                [(f.isoformat(), i, c.strip().lower(), d.strip()) for f, i, c, d in gastos],
            )
        return len(gastos)

    def borrar(self, gasto_id: int) -> bool:
        cur = self.con.execute("DELETE FROM gastos WHERE id = ?", (gasto_id,))
        self.con.commit()
        return cur.rowcount > 0

    def listar(self, mes: str | None = None, categoria: str | None = None) -> list[Gasto]:
        """mes en formato AAAA-MM."""
        sql = "SELECT id, fecha, importe, categoria, descripcion FROM gastos WHERE 1=1"
        params: list[str] = []
        if mes:
            sql += " AND substr(fecha, 1, 7) = ?"
            params.append(mes)
        if categoria:
            sql += " AND categoria = ?"
            params.append(categoria.strip().lower())
        sql += " ORDER BY fecha, id"
        return [
            Gasto(r[0], date.fromisoformat(r[1]), r[2], r[3], r[4])
            for r in self.con.execute(sql, params)
        ]

    def resumen(self, mes: str | None = None) -> dict[str, int]:
        """Total por categoría (céntimos), de mayor a menor."""
        totales: dict[str, int] = {}
        for g in self.listar(mes=mes):
            totales[g.categoria] = totales.get(g.categoria, 0) + g.importe
        return dict(sorted(totales.items(), key=lambda kv: kv[1], reverse=True))

    # --- presupuestos -----------------------------------------------------
    def fijar_presupuesto(self, categoria: str, limite: int) -> None:
        if limite <= 0:
            raise ValueError("El límite debe ser mayor que cero")
        self.con.execute(
            "INSERT INTO presupuestos (categoria, limite) VALUES (?, ?) "
            "ON CONFLICT(categoria) DO UPDATE SET limite = excluded.limite",
            (categoria.strip().lower(), limite),
        )
        self.con.commit()

    def presupuestos(self) -> dict[str, int]:
        return dict(self.con.execute("SELECT categoria, limite FROM presupuestos ORDER BY categoria"))
