"""Evidence Ledger: el mecanismo de trazabilidad del sistema.

Cada dato que el sistema muestra se registra aquí con su procedencia. Después,
toda afirmación del LLM se contrasta contra este registro antes de mostrarse: lo
que no tiene evidencia, no se muestra (docs/02 §2.3, ADR-008).
"""

from __future__ import annotations

import datetime as dt
import itertools
from collections.abc import Iterable, Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.domain import ClaimType


class Evidence(BaseModel):
    """Procedencia de un dato concreto."""

    model_config = ConfigDict(frozen=True)

    evidence_id: str
    claim_type: ClaimType
    source_system: str
    source_kind: str
    summary: str
    document: str | None = None
    locator: str | None = None
    document_path: str | None = None
    modified_at: dt.datetime | None = None
    model_id: str | None = None
    model_version: str | None = None
    value: Mapping[str, Any] | None = None
    extracted_at: dt.datetime = Field(
        default_factory=lambda: dt.datetime.now(dt.UTC)
    )

    def citation(self) -> str:
        if self.document and self.locator:
            return f"{self.document}!{self.locator}"
        if self.document:
            return self.document
        if self.model_id:
            return f"{self.model_id} v{self.model_version or '?'}"
        return self.source_system


class EvidenceLedger:
    """Registro de evidencias de una petición.

    Vive el tiempo de una respuesta. Los identificadores son locales a ella, de
    forma que el validador de salida solo puede aceptar citas emitidas en esta
    misma petición.
    """

    def __init__(self, prefix: str = "ev") -> None:
        self._prefix = prefix
        self._counter = itertools.count(1)
        self._items: dict[str, Evidence] = {}

    def record(
        self,
        *,
        claim_type: ClaimType,
        source_system: str,
        source_kind: str,
        summary: str,
        **extra: Any,
    ) -> Evidence:
        evidence_id = f"{self._prefix}_{next(self._counter):04d}"
        evidence = Evidence(
            evidence_id=evidence_id,
            claim_type=claim_type,
            source_system=source_system,
            source_kind=source_kind,
            summary=summary,
            **extra,
        )
        self._items[evidence_id] = evidence
        return evidence

    def fact_from_excel(
        self, summary: str, *, document: str, locator: str, **extra: Any
    ) -> Evidence:
        return self.record(
            claim_type=ClaimType.FACT,
            source_system="sharepoint",
            source_kind="excel",
            summary=summary,
            document=document,
            locator=locator,
            **extra,
        )

    def get(self, evidence_id: str) -> Evidence | None:
        return self._items.get(evidence_id)

    def known_ids(self) -> frozenset[str]:
        return frozenset(self._items)

    def all(self) -> tuple[Evidence, ...]:
        return tuple(self._items.values())

    def subset(self, evidence_ids: Iterable[str]) -> tuple[Evidence, ...]:
        return tuple(e for i in evidence_ids if (e := self._items.get(i)) is not None)

    def __len__(self) -> int:
        return len(self._items)
