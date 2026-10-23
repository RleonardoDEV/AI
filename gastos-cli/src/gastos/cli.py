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


def mes_anterior(mes: str) -> str:
    """'2026-01' -> '2025-12'."""
    anio, m = map(int, mes.split("-"))
    return f"{anio - 1}-12" if m == 1 else f"{anio}-{m - 1:02d}"


def comparar(actual: int, anterior: int) -> str:
    """Texto con la diferencia respecto al mes anterior."""
    if anterior == 0:
        return "nuevo" if actual else ""
    diff = actual - anterior
    signo = "+" if diff > 0 else ""
    pct = round(diff * 100 / anterior)
    return f"{signo}{formato(diff)} ({signo}{pct}%)"


class ErrorImportacion(Exception):
    pass


def leer_csv(fichero: TextIO) -> list[tuple[date, int, str, str]]:
    """Lee el formato de `exportar`. La columna id se ignora: se crean gastos nuevos."""
    lector = csv.DictReader(fichero)
    faltan = {"fecha", "importe", "categoria"} - set(lector.fieldnames or [])
    if faltan:
        raise ErrorImportacion(f"Faltan columnas: {', '.join(sorted(faltan))}")
    gastos = []
    for n, fila in enumerate(lector, start=2):  # la línea 1 es la cabecera
        try:
            fecha = tipo_fecha((fila["fecha"] or "").strip())
            importe = a_centimos((fila["importe"] or "").strip())
        except argparse.ArgumentTypeError as e:
            raise ErrorImportacion(f"Línea {n}: {e}") from None
        categoria = (fila["categoria"] or "").strip()
        if not categoria:
            raise ErrorImportacion(f"Línea {n}: falta la categoría")
        gastos.append((fecha, importe, categoria, fila.get("descripcion") or ""))
    return gastos


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

    ed = sub.add_parser("editar", help="Modificar un gasto por id")
    ed.add_argument("id", type=int)
    ed.add_argument("--importe", type=a_centimos)
    ed.add_argument("--categoria")
    ed.add_argument("--descripcion")
    ed.add_argument("--fecha", type=tipo_fecha)

    im = sub.add_parser("importar", help="Importar gastos desde un CSV (formato de `exportar`)")
    im.add_argument("fichero")

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

    elif cmd == "editar":
        campos = (args.fecha, args.importe, args.categoria, args.descripcion)
        if all(c is None for c in campos):
            print("Indica al menos un campo: --importe, --categoria, --descripcion o --fecha", file=sys.stderr)
            return 2
        if not almacen.editar(args.id, *campos):
            print(f"No existe el gasto #{args.id}", file=sys.stderr)
            return 1
        print(f"Gasto #{args.id} actualizado", file=out)

    elif cmd == "importar":
        try:
            with open(args.fichero, encoding="utf-8-sig", newline="") as f:
                gastos = leer_csv(f)
        except OSError as e:
            print(f"No se puede leer {args.fichero}: {e.strerror}", file=sys.stderr)
            return 1
        except ErrorImportacion as e:
            print(f"No se ha importado nada. {e}", file=sys.stderr)
            return 1
        print(f"{almacen.anadir_varios(gastos)} gastos importados", file=out)

    elif cmd == "resumen":
        mes = args.mes or date.today().strftime("%Y-%m")
        totales = almacen.resumen(mes)
        previos = almacen.resumen(mes_anterior(mes))
        limites = almacen.presupuestos()
        print(f"Resumen de {mes} (comparado con {mes_anterior(mes)})", file=out)
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
            if cambio := comparar(gastado, previos.get(cat, 0)):
                linea += f"  | {cambio}"
            print(linea, file=out)
        total, total_previo = sum(totales.values()), sum(previos.values())
        linea = f"  {'TOTAL':<14} {formato(total):>12}"
        if cambio := comparar(total, total_previo):
            linea += f"  | {cambio}"
        print(linea, file=out)

    elif cmd == "presupuesto":
        almacen.fijar_presupuesto(args.categoria, args.limite)
        print(f"Presupuesto de {args.categoria.lower()}: {formato(args.limite)} al mes", file=out)

    elif cmd == "exportar":
        w = csv.writer(out)
        w.writerow(["id", "fecha", "importe", "categoria", "descripcion"])
        for g in almacen.listar(mes=args.mes):
            w.writerow([g.id, g.fecha.isoformat(), f"{g.importe / 100:.2f}", g.categoria, g.descripcion])
    return 0
