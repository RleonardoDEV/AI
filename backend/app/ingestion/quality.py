"""Informe de calidad de datos de una ingesta.

Si una parte importante del fichero no se pudo validar, el Health del proyecto
no se calcula con lo que quedó: se marca UNKNOWN. Es preferible decir "no tengo
datos fiables" a dar un verde apoyado en la mitad de las filas (docs/00, P4).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.ingestion.excel.parser import ParseResult


@dataclass(frozen=True, slots=True)
class SourceQuality:
    source: str
    sheet_name: str
    header_row: int
    valid_rows: int
    quarantined_rows: int
    reasons: dict[str, int]
    missing_columns: tuple[str, ...]
    unmapped_headers: tuple[str, ...]

    @property
    def total_rows(self) -> int:
        return self.valid_rows + self.quarantined_rows

    @property
    def quarantine_ratio(self) -> float:
        return self.quarantined_rows / self.total_rows if self.total_rows else 0.0


@dataclass(frozen=True, slots=True)
class DataQualityReport:
    sources: tuple[SourceQuality, ...]
    threshold: float

    @classmethod
    def from_results(
        cls, results: dict[str, ParseResult], *, threshold: float = 0.20
    ) -> DataQualityReport:
        return cls(
            sources=tuple(
                SourceQuality(
                    source=name,
                    sheet_name=result.sheet_name,
                    header_row=result.header_row,
                    valid_rows=len(result.rows),
                    quarantined_rows=len(result.quarantined),
                    reasons=result.reasons(),
                    missing_columns=result.missing_columns,
                    unmapped_headers=result.unmapped_headers,
                )
                for name, result in results.items()
            ),
            threshold=threshold,
        )

    @property
    def unreliable_sources(self) -> tuple[SourceQuality, ...]:
        return tuple(s for s in self.sources if s.quarantine_ratio > self.threshold)

    @property
    def is_reliable(self) -> bool:
        return not self.unreliable_sources

    def summary_lines(self) -> tuple[str, ...]:
        lines = []
        for source in self.sources:
            detail = ", ".join(f"{r}×{n}" for r, n in source.reasons.items()) or "sin incidencias"
            flag = "  ⚠ POR DEBAJO DEL UMBRAL" if source.quarantine_ratio > self.threshold else ""
            lines.append(
                f"{source.source:<14} hoja '{source.sheet_name}' cabecera fila {source.header_row}"
                f" · {source.valid_rows} válidas / {source.quarantined_rows} en cuarentena"
                f" ({source.quarantine_ratio:.0%}) · {detail}{flag}"
            )
        return tuple(lines)
