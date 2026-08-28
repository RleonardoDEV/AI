"""Carga de los contratos de datos (schema mappings) desde YAML.

Adaptar el sistema a un fichero Excel real consiste en editar el YAML, nunca en
tocar el código (docs/00, P4).
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any, Literal

import yaml

from app.ingestion.excel.coercion import COERCERS, normalize_key

MAPPINGS_DIR = Path(__file__).parent / "mappings"


class SchemaMappingError(ValueError):
    """El contrato de datos es inválido o no encaja con el fichero."""


@dataclass(frozen=True, slots=True)
class ColumnSpec:
    field: str
    aliases: tuple[str, ...]
    type: str
    required: bool = False

    @property
    def normalized_aliases(self) -> frozenset[str]:
        return frozenset(normalize_key(a) for a in (*self.aliases, self.field))


@dataclass(frozen=True, slots=True)
class SchemaMapping:
    name: str
    model_name: str
    sheet_names: tuple[str, ...]
    header_detect: Literal["auto", "fixed"]
    header_row: int | None
    max_scan_rows: int
    columns: tuple[ColumnSpec, ...]

    @property
    def required_columns(self) -> tuple[ColumnSpec, ...]:
        return tuple(c for c in self.columns if c.required)

    def column_for_header(self, header: Any) -> ColumnSpec | None:
        key = normalize_key(header)
        if not key:
            return None
        for spec in self.columns:
            if key in spec.normalized_aliases:
                return spec
        return None


def _parse(raw: dict[str, Any], *, source: str) -> SchemaMapping:
    try:
        sheet = raw["sheet"]
        header = raw["header"]
        columns_raw: dict[str, Any] = raw["columns"]
        model_name: str = raw["model"]
    except KeyError as exc:
        raise SchemaMappingError(f"{source}: falta la sección {exc}") from exc

    detect = header.get("detect", "auto")
    if detect not in ("auto", "fixed"):
        raise SchemaMappingError(f"{source}: header.detect debe ser 'auto' o 'fixed'")
    if detect == "fixed" and not header.get("row"):
        raise SchemaMappingError(f"{source}: header.detect='fixed' exige header.row")

    columns: list[ColumnSpec] = []
    for field, spec in columns_raw.items():
        col_type = spec.get("type", "text")
        if col_type not in COERCERS:
            raise SchemaMappingError(
                f"{source}: la columna '{field}' usa el tipo desconocido '{col_type}'. "
                f"Tipos admitidos: {sorted(COERCERS)}"
            )
        columns.append(
            ColumnSpec(
                field=field,
                aliases=tuple(spec.get("aliases", ())),
                type=col_type,
                required=bool(spec.get("required", False)),
            )
        )

    if not columns:
        raise SchemaMappingError(f"{source}: el contrato no define ninguna columna")

    return SchemaMapping(
        name=raw.get("name", source),
        model_name=model_name,
        sheet_names=tuple(sheet.get("names", ())),
        header_detect=detect,
        header_row=header.get("row"),
        max_scan_rows=int(header.get("max_scan_rows", 30)),
        columns=tuple(columns),
    )


def load_mapping_from_path(path: Path) -> SchemaMapping:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise SchemaMappingError(f"{path.name}: el YAML no contiene un objeto")
    return _parse(raw, source=path.name)


@cache
def load_mapping(name: str) -> SchemaMapping:
    path = MAPPINGS_DIR / f"{name}.yaml"
    if not path.exists():
        available = sorted(p.stem for p in MAPPINGS_DIR.glob("*.yaml"))
        raise SchemaMappingError(f"No existe el contrato '{name}'. Disponibles: {available}")
    return load_mapping_from_path(path)


def available_mappings() -> tuple[str, ...]:
    return tuple(sorted(p.stem for p in MAPPINGS_DIR.glob("*.yaml")))
