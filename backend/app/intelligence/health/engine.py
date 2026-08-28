"""Motor de Project Health.

ADR-005: esto es código determinista, no un LLM. La misma entrada produce
siempre la misma salida, y cada razón lleva su evidencia.
"""

from __future__ import annotations

import datetime as dt
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from app.intelligence.evidence import Evidence, EvidenceLedger
from app.schemas.domain import (
    BudgetRow,
    ClaimType,
    HealthDimension,
    HealthStatus,
    ResourceRow,
    RiskRow,
    TaskRow,
    TaskStatus,
)

RULES_PATH = Path(__file__).parent / "rules.yaml"


@lru_cache(maxsize=1)
def load_rules(path: Path = RULES_PATH) -> dict[str, Any]:
    return yaml.safe_load(path.read_text(encoding="utf-8"))  # type: ignore[no-any-return]


@dataclass(frozen=True, slots=True)
class ProjectData:
    """Todo lo que el motor necesita. Se construye desde la ingesta."""

    project_name: str
    as_of: dt.date
    tasks: tuple[TaskRow, ...] = ()
    risks: tuple[RiskRow, ...] = ()
    resources: tuple[ResourceRow, ...] = ()
    budget: tuple[BudgetRow, ...] = ()
    # Fuentes cuya proporción de filas en cuarentena supera el umbral. Las
    # dimensiones que dependen de ellas se marcan UNKNOWN en lugar de
    # calcularse con la mitad de las filas (docs/00, P4).
    unreliable_sources: frozenset[str] = frozenset()


@dataclass(frozen=True, slots=True)
class Reason:
    text: str
    evidence: Evidence


@dataclass(frozen=True, slots=True)
class DimensionResult:
    dimension: HealthDimension
    status: HealthStatus
    reasons: tuple[Reason, ...]

    @property
    def is_known(self) -> bool:
        return self.status is not HealthStatus.UNKNOWN


@dataclass(frozen=True, slots=True)
class HealthResult:
    project_name: str
    as_of: dt.date
    rules_version: str
    overall: HealthStatus
    dimensions: tuple[DimensionResult, ...]

    def dimension(self, name: HealthDimension) -> DimensionResult | None:
        return next((d for d in self.dimensions if d.dimension is name), None)

    @property
    def all_reasons(self) -> tuple[Reason, ...]:
        return tuple(r for d in self.dimensions for r in d.reasons)


def _grade(
    value: float, thresholds: dict[str, float], *, lower_is_worse: bool = False
) -> HealthStatus:
    """Clasifica un valor según los tres umbrales de la regla."""
    yellow, orange, red = thresholds["yellow"], thresholds["orange"], thresholds["red"]
    if lower_is_worse:
        if value <= red:
            return HealthStatus.RED
        if value <= orange:
            return HealthStatus.ORANGE
        if value <= yellow:
            return HealthStatus.YELLOW
        return HealthStatus.GREEN
    if value >= red:
        return HealthStatus.RED
    if value >= orange:
        return HealthStatus.ORANGE
    if value >= yellow:
        return HealthStatus.YELLOW
    return HealthStatus.GREEN


def _worst(statuses: Sequence[HealthStatus]) -> HealthStatus:
    known = [s for s in statuses if s is not HealthStatus.UNKNOWN]
    return max(known, key=lambda s: s.rank) if known else HealthStatus.UNKNOWN


def _unknown(
    dimension: HealthDimension, ledger: EvidenceLedger, why: str
) -> DimensionResult:
    """Una dimensión sin datos fiables es UNKNOWN, nunca GREEN."""
    evidence = ledger.record(
        claim_type=ClaimType.FACT,
        source_system="rules",
        source_kind="data_availability",
        summary=why,
    )
    return DimensionResult(dimension, HealthStatus.UNKNOWN, (Reason(why, evidence),))


def _assess_schedule(
    data: ProjectData, rules: dict[str, Any], ledger: EvidenceLedger
) -> DimensionResult:
    if bad := sorted(data.unreliable_sources & {"project_plan"}):
        return _unreliable(HealthDimension.SCHEDULE, ledger, bad)
    if not data.tasks:
        return _unknown(HealthDimension.SCHEDULE, ledger, "No hay tareas cargadas.")

    thresholds = rules["schedule"]
    open_tasks = [t for t in data.tasks if t.is_open]
    late = [t for t in open_tasks if t.days_late(data.as_of) > 0]
    late_critical = [t for t in late if t.critical]

    statuses: list[HealthStatus] = []
    reasons: list[Reason] = []

    critical_status = _grade(len(late_critical), thresholds["delayed_critical_tasks"])
    statuses.append(critical_status)
    if late_critical:
        reasons.append(
            Reason(
                f"{len(late_critical)} tareas críticas retrasadas",
                ledger.fact_from_excel(
                    f"{len(late_critical)} tareas críticas con fecha de fin superada",
                    document="Project Plan.xlsx",
                    locator="Tasks",
                    value={"task_ids": [t.task_id for t in late_critical][:20]},
                ),
            )
        )

    if open_tasks:
        ratio = 100 * len(late) / len(open_tasks)
        statuses.append(_grade(ratio, thresholds["delayed_ratio_pct"]))
        if late:
            reasons.append(
                Reason(
                    f"{ratio:.0f} % de las tareas abiertas van con retraso "
                    f"({len(late)} de {len(open_tasks)})",
                    ledger.fact_from_excel(
                        "Proporción de tareas abiertas retrasadas",
                        document="Project Plan.xlsx",
                        locator="Tasks",
                        value={"late": len(late), "open": len(open_tasks)},
                    ),
                )
            )

    milestones = [t for t in open_tasks if t.milestone and t.planned_end is not None]
    if milestones:
        next_milestone = min(milestones, key=lambda t: t.planned_end or dt.date.max)
        delay = next_milestone.days_late(data.as_of)
        statuses.append(_grade(delay, thresholds["next_milestone_delay_days"]))
        if delay > 0:
            reasons.append(
                Reason(
                    f"El hito «{next_milestone.task}» acumula {delay} días de retraso",
                    ledger.fact_from_excel(
                        f"Hito {next_milestone.task_id} retrasado {delay} días",
                        document="Project Plan.xlsx",
                        locator=f"Tasks[{next_milestone.task_id}]",
                        value={"planned_end": str(next_milestone.planned_end)},
                    ),
                )
            )

    return DimensionResult(HealthDimension.SCHEDULE, _worst(statuses), tuple(reasons))


def _assess_budget(
    data: ProjectData, rules: dict[str, Any], ledger: EvidenceLedger
) -> DimensionResult:
    if bad := sorted(data.unreliable_sources & {"project_plan", "budget"}):
        return _unreliable(HealthDimension.BUDGET, ledger, bad)
    thresholds = rules["budget"]
    statuses: list[HealthStatus] = []
    reasons: list[Reason] = []

    planned = sum(b.planned_amount or 0 for b in data.budget)
    actual = sum(b.actual_amount or 0 for b in data.budget)
    if planned > 0:
        variance = 100 * (actual - planned) / planned
        statuses.append(_grade(variance, thresholds["cost_variance_pct"]))
        if variance > 0:
            reasons.append(
                Reason(
                    f"{variance:.0f} % de desviación de coste sobre lo planificado",
                    ledger.fact_from_excel(
                        "Desviación de coste",
                        document="Budget.xlsx",
                        locator="Budget",
                        value={"planned": planned, "actual": actual},
                    ),
                )
            )

    est = sum(t.estimated_hours or 0 for t in data.tasks)
    act = sum(t.actual_hours or 0 for t in data.tasks)
    if est == 0:
        est = sum(b.planned_hours or 0 for b in data.budget)
        act = sum(b.actual_hours or 0 for b in data.budget)
    if est > 0:
        variance = 100 * (act - est) / est
        statuses.append(_grade(variance, thresholds["hours_variance_pct"]))
        if variance > 0:
            reasons.append(
                Reason(
                    f"{variance:.0f} % de desviación en horas respecto a lo estimado",
                    ledger.fact_from_excel(
                        "Desviación de horas",
                        document="Project Plan.xlsx",
                        locator="Tasks",
                        value={"estimated_hours": est, "actual_hours": act},
                    ),
                )
            )

    if not statuses:
        return _unknown(
            HealthDimension.BUDGET,
            ledger,
            "No hay datos de presupuesto ni de horas para calcular esta dimensión.",
        )
    return DimensionResult(HealthDimension.BUDGET, _worst(statuses), tuple(reasons))


def _assess_resources(
    data: ProjectData, rules: dict[str, Any], ledger: EvidenceLedger
) -> DimensionResult:
    if bad := sorted(data.unreliable_sources & {"resources"}):
        return _unreliable(HealthDimension.RESOURCES, ledger, bad)
    if not data.resources:
        return _unknown(HealthDimension.RESOURCES, ledger, "No hay datos de recursos cargados.")

    thresholds = rules["resources"]
    statuses: list[HealthStatus] = []
    reasons: list[Reason] = []

    allocations = [r.allocation_pct for r in data.resources if r.allocation_pct is not None]
    if allocations:
        availability = sum(min(a, 100) for a in allocations) / len(allocations)
        statuses.append(
            _grade(availability, thresholds["availability_pct"], lower_is_worse=True)
        )
        if availability < thresholds["availability_pct"]["yellow"]:
            reasons.append(
                Reason(
                    f"Disponibilidad media del equipo del {availability:.0f} %",
                    ledger.fact_from_excel(
                        "Disponibilidad media del equipo",
                        document="Resources.xlsx",
                        locator="Resources",
                        value={"availability_pct": round(availability, 1)},
                    ),
                )
            )

        overallocated = [r for r in data.resources if (r.allocation_pct or 0) > 100]
        statuses.append(_grade(len(overallocated), thresholds["overallocated_people"]))
        if overallocated:
            reasons.append(
                Reason(
                    f"{len(overallocated)} "
                    f"{'persona asignada' if len(overallocated) == 1 else 'personas asignadas'} "
                    f"por encima del 100 %",
                    ledger.fact_from_excel(
                        "Personas sobreasignadas",
                        document="Resources.xlsx",
                        locator="Resources",
                        value={"people": [r.resource for r in overallocated][:20]},
                    ),
                )
            )

    absent_key = [
        r for r in data.resources if r.key_resource and (r.absence_days or 0) > 0
    ]
    if absent_key:
        worst_absence = max(r.absence_days or 0 for r in absent_key)
        statuses.append(_grade(worst_absence, thresholds["key_resource_absence_days"]))
        reasons.append(
            Reason(
                f"Un recurso clave estará ausente {worst_absence:.0f} días",
                ledger.fact_from_excel(
                    "Ausencia de recurso clave",
                    document="Resources.xlsx",
                    locator="Resources",
                    value={"days": worst_absence},
                ),
            )
        )

    if not statuses:
        return _unknown(
            HealthDimension.RESOURCES,
            ledger,
            "Los recursos cargados no tienen datos de asignación ni de ausencias.",
        )
    return DimensionResult(HealthDimension.RESOURCES, _worst(statuses), tuple(reasons))


def _assess_dependencies(
    data: ProjectData, rules: dict[str, Any], ledger: EvidenceLedger
) -> DimensionResult:
    if bad := sorted(data.unreliable_sources & {"project_plan"}):
        return _unreliable(HealthDimension.DEPENDENCIES, ledger, bad)
    if not data.tasks:
        return _unknown(HealthDimension.DEPENDENCIES, ledger, "No hay tareas cargadas.")

    thresholds = rules["dependencies"]
    blocked = [t for t in data.tasks if t.status is TaskStatus.BLOCKED]
    statuses = [_grade(len(blocked), thresholds["blocked_tasks"])]
    reasons: list[Reason] = []

    if blocked:
        reasons.append(
            Reason(
                f"{len(blocked)} tareas bloqueadas",
                ledger.fact_from_excel(
                    f"{len(blocked)} tareas en estado BLOCKED",
                    document="Project Plan.xlsx",
                    locator="Tasks",
                    value={"task_ids": [t.task_id for t in blocked][:20]},
                ),
            )
        )
        datable = [t for t in blocked if t.planned_start is not None]
        if datable:
            oldest = min(datable, key=lambda t: t.planned_start or dt.date.max)
            days = max(0, (data.as_of - (oldest.planned_start or data.as_of)).days)
            statuses.append(_grade(days, thresholds["oldest_block_days"]))
            if days > 0:
                reasons.append(
                    Reason(
                        f"La tarea bloqueada más antigua lleva {days} días sin avanzar "
                        f"desde su fecha de inicio prevista",
                        ledger.fact_from_excel(
                            f"Bloqueo más antiguo: {oldest.task_id}",
                            document="Project Plan.xlsx",
                            locator=f"Tasks[{oldest.task_id}]",
                            value={"days_blocked": days},
                        ),
                    )
                )

    return DimensionResult(HealthDimension.DEPENDENCIES, _worst(statuses), tuple(reasons))


def _unreliable(
    dimension: HealthDimension, ledger: EvidenceLedger, sources: Sequence[str]
) -> DimensionResult:
    listed = ", ".join(sources)
    return _unknown(
        dimension,
        ledger,
        f"La fuente '{listed}' tiene demasiadas filas en cuarentena. No se calcula "
        f"esta dimensión con datos parciales: corrige el fichero y vuelve a ingerir.",
    )


_NO_SOURCE = (
    "Las plantillas actuales no contienen una fuente de datos para esta dimensión. "
    "Se marca UNKNOWN en lugar de asumir que va bien."
)


def compute_health(data: ProjectData, ledger: EvidenceLedger | None = None) -> HealthResult:
    """Calcula el Health del proyecto a partir de datos ya validados."""
    rules = load_rules()
    # `is None`, no `or`: EvidenceLedger define __len__, así que un registro
    # vacío es falsy y `ledger or EvidenceLedger()` descartaría el del llamante.
    if ledger is None:
        ledger = EvidenceLedger()

    dimensions = [
        _assess_schedule(data, rules, ledger),
        _assess_budget(data, rules, ledger),
        _assess_resources(data, rules, ledger),
        _assess_dependencies(data, rules, ledger),
        # Sin fuente de datos en el contrato canónico actual (docs/08 §G).
        _unknown(HealthDimension.SCOPE, ledger, _NO_SOURCE),
        _unknown(HealthDimension.QUALITY, ledger, _NO_SOURCE),
        _unknown(HealthDimension.CUSTOMER, ledger, _NO_SOURCE),
    ]

    return HealthResult(
        project_name=data.project_name,
        as_of=data.as_of,
        rules_version=rules["version"],
        overall=_aggregate(dimensions, rules),
        dimensions=tuple(dimensions),
    )


def _aggregate(dimensions: Sequence[DimensionResult], rules: dict[str, Any]) -> HealthStatus:
    """Agrega las dimensiones en un Overall.

    No es una media aritmética: una media convierte un RED en YELLOW cuando el
    resto va bien, y eso oculta justo lo que hay que ver. El Overall nunca queda
    más de un nivel por debajo de la peor dimensión (docs/05 §1).
    """
    config = rules["aggregation"]
    weights: dict[str, float] = rules["weights"]

    known = [d for d in dimensions if d.is_known]
    if not known or len(known) / len(dimensions) < (1 - config["unknown_ratio_limit"]):
        return HealthStatus.UNKNOWN

    total_weight = sum(weights.get(d.dimension.value, 0.0) for d in known)
    if total_weight <= 0:
        return HealthStatus.UNKNOWN

    weighted = sum(
        weights.get(d.dimension.value, 0.0) * d.status.rank for d in known
    ) / total_weight

    worst = _worst([d.status for d in known])
    floor = worst.rank - config["max_levels_below_worst"]
    return HealthStatus.from_rank(max(round(weighted), floor))
