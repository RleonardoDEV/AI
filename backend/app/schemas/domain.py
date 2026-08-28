"""Modelo de dominio canónico.

Todo lo que entra por ingesta se normaliza a estas formas antes de tocar la base
de datos. Un valor que no encaja no se convierte al valor por defecto: la fila va
a cuarentena y aparece en el informe de calidad (docs/00, problema P4).
"""

from __future__ import annotations

import datetime as dt
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field


class TaskStatus(StrEnum):
    NOT_STARTED = "NOT_STARTED"
    IN_PROGRESS = "IN_PROGRESS"
    BLOCKED = "BLOCKED"
    DONE = "DONE"
    CANCELLED = "CANCELLED"


class RiskStatus(StrEnum):
    OPEN = "OPEN"
    MITIGATING = "MITIGATING"
    CLOSED = "CLOSED"
    ACCEPTED = "ACCEPTED"


class Level(StrEnum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class HealthStatus(StrEnum):
    """Escala de Health. UNKNOWN es un estado de primera clase.

    Si no hay datos fiables, el sistema lo dice. Nunca pinta verde por ausencia
    de datos (docs/05 §1).
    """

    GREEN = "GREEN"
    YELLOW = "YELLOW"
    ORANGE = "ORANGE"
    RED = "RED"
    UNKNOWN = "UNKNOWN"

    @property
    def rank(self) -> int:
        return _HEALTH_RANK[self]

    @classmethod
    def from_rank(cls, rank: int) -> HealthStatus:
        clamped = max(0, min(3, rank))
        return _RANK_TO_HEALTH[clamped]


_HEALTH_RANK: dict[HealthStatus, int] = {
    HealthStatus.GREEN: 0,
    HealthStatus.YELLOW: 1,
    HealthStatus.ORANGE: 2,
    HealthStatus.RED: 3,
    HealthStatus.UNKNOWN: -1,
}
_RANK_TO_HEALTH: dict[int, HealthStatus] = {
    0: HealthStatus.GREEN,
    1: HealthStatus.YELLOW,
    2: HealthStatus.ORANGE,
    3: HealthStatus.RED,
}


class HealthDimension(StrEnum):
    SCHEDULE = "SCHEDULE"
    BUDGET = "BUDGET"
    RESOURCES = "RESOURCES"
    SCOPE = "SCOPE"
    QUALITY = "QUALITY"
    DEPENDENCIES = "DEPENDENCIES"
    CUSTOMER = "CUSTOMER"


class ClaimType(StrEnum):
    """Tipo de dato de cada afirmación que el sistema muestra (docs/02 §2.3)."""

    FACT = "FACT"
    PREDICTION = "PREDICTION"
    INFERENCE = "INFERENCE"
    RECOMMENDATION = "RECOMMENDATION"


class _Row(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")


class TaskRow(_Row):
    task_id: str
    task: str
    owner: str | None = None
    planned_start: dt.date | None = None
    planned_end: dt.date | None = None
    actual_start: dt.date | None = None
    actual_end: dt.date | None = None
    status: TaskStatus
    estimated_hours: float | None = Field(default=None, ge=0)
    actual_hours: float | None = Field(default=None, ge=0)
    milestone: bool = False
    depends_on: tuple[str, ...] = ()
    critical: bool = False

    @property
    def is_open(self) -> bool:
        return self.status not in (TaskStatus.DONE, TaskStatus.CANCELLED)

    def days_late(self, as_of: dt.date) -> int:
        """Días de retraso respecto a la fecha planificada de fin.

        Una tarea cerrada se mide contra su fecha real; una abierta, contra la
        fecha de referencia. Sin fecha planificada no hay retraso medible.
        """
        if self.planned_end is None:
            return 0
        reference = self.actual_end if self.status is TaskStatus.DONE else as_of
        if reference is None:
            return 0
        return max(0, (reference - self.planned_end).days)


class RiskRow(_Row):
    risk_id: str
    description: str
    category: str | None = None
    probability: Level | None = None
    impact: Level | None = None
    owner: str | None = None
    status: RiskStatus
    mitigation: str | None = None
    identified_on: dt.date | None = None
    due_date: dt.date | None = None

    @property
    def is_open(self) -> bool:
        return self.status in (RiskStatus.OPEN, RiskStatus.MITIGATING)

    @property
    def severity_score(self) -> int:
        """0-9. Sin probabilidad o impacto no se inventa: puntúa 0."""
        weights = {Level.LOW: 1, Level.MEDIUM: 2, Level.HIGH: 3}
        if self.probability is None or self.impact is None:
            return 0
        return weights[self.probability] * weights[self.impact]


class ResourceRow(_Row):
    resource: str
    role: str | None = None
    allocation_pct: float | None = Field(default=None, ge=0, le=200)
    available_from: dt.date | None = None
    available_to: dt.date | None = None
    absence_days: float | None = Field(default=None, ge=0)
    key_resource: bool = False


class BudgetRow(_Row):
    item: str
    category: str | None = None
    planned_amount: float | None = None
    actual_amount: float | None = None
    currency: str | None = None
    period: str | None = None
    planned_hours: float | None = Field(default=None, ge=0)
    actual_hours: float | None = Field(default=None, ge=0)
