"""CLI de desarrollo.

`python -m app.cli demo` ejecuta la cadena completa sobre datos sintéticos:
parseo → validación → informe de calidad → Project Health con evidencias.
No necesita credenciales de Microsoft ni base de datos.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys

from app.dev import synthetic
from app.ingestion.excel.mapping import load_mapping
from app.ingestion.excel.parser import ParseResult, parse_workbook
from app.ingestion.quality import DataQualityReport
from app.intelligence.evidence import EvidenceLedger
from app.intelligence.health.engine import ProjectData, compute_health
from app.schemas.domain import HealthStatus

_MARK = {
    HealthStatus.GREEN: "GREEN ",
    HealthStatus.YELLOW: "YELLOW",
    HealthStatus.ORANGE: "ORANGE",
    HealthStatus.RED: "RED   ",
    HealthStatus.UNKNOWN: "UNKNWN",
}


def _rule(title: str = "") -> None:
    print(f"\n{title}\n{'─' * 78}" if title else "─" * 78)


def run_demo(as_of: dt.date) -> int:
    print("=" * 78)
    print("  AI PROJECT MANAGER ASSISTANT — demostración con DATOS SINTÉTICOS")
    print("  Estos datos NO corresponden a ningún proyecto real.")
    print("=" * 78)

    results: dict[str, ParseResult] = {
        name: parse_workbook(builder(), load_mapping(name))
        for name, builder in synthetic.WORKBOOKS.items()
    }

    _rule("1 · INGESTA Y CALIDAD DE DATOS")
    report = DataQualityReport.from_results(results)
    for line in report.summary_lines():
        print(f"  {line}")
    print(f"\n  Fuentes fiables: {'sí' if report.is_reliable else 'NO'}")

    _rule("2 · FILAS EN CUARENTENA (no se descartan en silencio)")
    for name, result in results.items():
        for row in result.quarantined:
            detail = f" — {row.detail}" if row.detail else ""
            value = f" valor={row.raw_value!r}" if row.raw_value else ""
            print(f"  {name:<14} fila {row.row_number:>3}  {row.reason:<28}"
                  f" campo={row.field_name or '-'}{value}{detail}")

    ledger = EvidenceLedger()
    unreliable = frozenset(s.source for s in report.unreliable_sources)
    data = ProjectData(
        project_name="Project X",
        as_of=as_of,
        unreliable_sources=unreliable,
        tasks=results["project_plan"].rows,  # type: ignore[arg-type]
        risks=results["risks"].rows,  # type: ignore[arg-type]
        resources=results["resources"].rows,  # type: ignore[arg-type]
        budget=results["budget"].rows,  # type: ignore[arg-type]
    )
    health = compute_health(data, ledger)

    _rule(f"3 · PROJECT HEALTH — {health.project_name} (a {health.as_of})")
    print(f"  Overall Health: {health.overall.value}"
          f"        [reglas v{health.rules_version} · determinista]\n")
    for dimension in health.dimensions:
        print(f"  {_MARK[dimension.status]}  {dimension.dimension.value}")
        for reason in dimension.reasons:
            print(f"           · {reason.text}")
            print(f"             └─ {reason.evidence.claim_type.value}"
                  f" · {reason.evidence.citation()}"
                  f" · {reason.evidence.evidence_id}")

    _rule("4 · TRAZABILIDAD")
    print(f"  {len(ledger)} evidencias registradas. Toda afirmación mostrada arriba")
    print("  se puede resolver contra el Evidence Ledger; lo que no se resuelve,")
    print("  no se muestra (ADR-008).")
    print()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="app.cli")
    sub = parser.add_subparsers(dest="command", required=True)
    demo = sub.add_parser("demo", help="Ejecuta la cadena completa con datos sintéticos")
    demo.add_argument(
        "--as-of",
        type=dt.date.fromisoformat,
        default=dt.date(2026, 8, 28),
        help="Fecha de referencia para el cálculo (YYYY-MM-DD)",
    )
    args = parser.parse_args(argv)
    if args.command == "demo":
        return run_demo(args.as_of)
    return 1


if __name__ == "__main__":
    sys.exit(main())
