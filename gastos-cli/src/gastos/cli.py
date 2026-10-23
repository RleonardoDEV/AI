"""Interfaz de línea de comandos."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import TextIO

from gastos import __version__
from gastos.db import Almacen, ruta_por_defecto


def a_centimos(texto: str) -> int:
    """'12,50' o '12.50' -> 1250."""
    try:
        valor = Decimal(texto.replace(",", "."))
        centimos = int((valor * 100).quantize(Decimal(1)))
    except (InvalidOperation, ValueError):
        raise argparse.ArgumentTypeError(f"Importe no válido: {texto!r}") from None
    if centimos <= 0:
        raise argparse.ArgumentTypeError("El importe debe ser mayor que cero")
    return centimos


def formato(centimos: int) -> str:
    """1250 -> '12,50 €'."""
    euros, cent = divmod(abs(centimos), 100)
    signo = "-" if centimos < 0 else ""
    return f"{signo}{euros:,}".replace(",", ".") + f",{cent:02d} €"


def tipo_fecha(texto: str) -> date:
    try:
        return date.fromisoformat(texto)
    except ValueError:
        raise argparse.ArgumentTypeError("Usa el formato AAAA-MM-DD") from None


def tipo_mes(texto: str) -> str:
    if not re.fullmatch(r"\d{4}-(0[1-9]|1[0-2])", texto):
        raise argparse.ArgumentTypeError("Usa el formato AAAA-MM")
    return texto


def construir_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="gastos", description="Gestor de gastos personales.")
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    p.add_argument("--db", help="Ruta del fichero de datos (por defecto ~/.gastos.db)")
    sub = p.add_subparsers(dest="comando", required=True)

    a = sub.add_parser("anadir", aliases=["add"], help="Registrar un gasto")
    a.add_argument("importe", type=a_centimos, help="Ej.: 12,50")
    a.add_argument("categoria", help="Ej.: comida, transporte")
    a.add_argument("descripcion", nargs="?", default="")
    a.add_argument("--fecha", type=tipo_fecha, default=None, help="AAAA-MM-DD (por defecto hoy)")

    l = sub.add_parser("listar", aliases=["ls"], help="Listar gastos")
    l.add_argument("--mes", type=tipo_mes)
    l.add_argument("--categoria")

    b = sub.add_parser("borrar", aliases=["rm"], help="Borrar un gasto por id")
    b.add_argument("id", type=int)

    r = sub.add_parser("resumen", help="Total por categoría y estado del presupuesto")
    r.add_argument("--mes", type=tipo_mes, help="Por defecto, el mes actual")

    pr = sub.add_parser("presupuesto", help="Fijar límite mensual de una categoría")
    pr.add_argument("categoria")
    pr.add_argument("limite", type=a_centimos)

    e = sub.add_parser("exportar", help="Exportar a CSV (salida estándar)")
    e.add_argument("--mes", type=tipo_mes)
    return p


def main(argv: list[str] | None = None, salida: TextIO | None = None) -> int:
    out = salida or sys.stdout
    args = construir_parser().parse_args(argv)
    almacen = Almacen(args.db or ruta_por_defecto())
    try:
        return _ejecutar(args, almacen, out)
    finally:
        almacen.cerrar()


def _ejecutar(args: argparse.Namespace, almacen: Almacen, out: TextIO) -> int:
    cmd = args.comando
    if cmd in ("anadir", "add"):
        gid = almacen.anadir(args.fecha or date.today(), args.importe, args.categoria, args.descripcion)
        print(f"Gasto #{gid} registrado: {formato(args.importe)} en {args.categoria.lower()}", file=out)

    elif cmd in ("listar", "ls"):
        gastos = almacen.listar(mes=args.mes, categoria=args.categoria)
        if not gastos:
            print("No hay gastos.", file=out)
            return 0
        for g in gastos:
            print(f"#{g.id:<4} {g.fecha}  {formato(g.importe):>12}  {g.categoria:<14} {g.descripcion}", file=out)
        print(f"{'':>17}{'-' * 12}\n{'Total':<17}{formato(sum(g.importe for g in gastos)):>12}", file=out)

    elif cmd in ("borrar", "rm"):
        if not almacen.borrar(args.id):
            print(f"No existe el gasto #{args.id}", file=sys.stderr)
            return 1
        print(f"Gasto #{args.id} borrado", file=out)

    elif cmd == "resumen":
        mes = args.mes or date.today().strftime("%Y-%m")
        totales = almacen.resumen(mes)
        limites = almacen.presupuestos()
        print(f"Resumen de {mes}", file=out)
        if not totales and not limites:
            print("No hay gastos.", file=out)
            return 0
        for cat in list(totales) + [c for c in limites if c not in totales]:
            gastado = totales.get(cat, 0)
            linea = f"  {cat:<14} {formato(gastado):>12}"
            if cat in limites:
                pct = gastado * 100 // limites[cat]
                aviso = "  ¡SUPERADO!" if gastado > limites[cat] else ""
                linea += f"  de {formato(limites[cat])} ({pct}%){aviso}"
            print(linea, file=out)
        print(f"  {'TOTAL':<14} {formato(sum(totales.values())):>12}", file=out)

    elif cmd == "presupuesto":
        almacen.fijar_presupuesto(args.categoria, args.limite)
        print(f"Presupuesto de {args.categoria.lower()}: {formato(args.limite)} al mes", file=out)

    elif cmd == "exportar":
        w = csv.writer(out)
        w.writerow(["id", "fecha", "importe", "categoria", "descripcion"])
        for g in almacen.listar(mes=args.mes):
            w.writerow([g.id, g.fecha.isoformat(), f"{g.importe / 100:.2f}", g.categoria, g.descripcion])
    return 0
