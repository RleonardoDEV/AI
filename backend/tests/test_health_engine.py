from __future__ import annotations

import datetime as dt

import pytest

from app.ingestion.excel.mapping import load_mapping
from app.ingestion.excel.parser import parse_workbook
from app.intelligence.evidence import EvidenceLedger
from app.intelligence.health.engine import (
    DimensionResult,
    ProjectData,
    Reason,
    _aggregate,
    compute_health,
    load_rules,
)
from app.schemas.domain import ClaimType, HealthDimension, HealthStatus, TaskRow, TaskStatus

AS_OF = dt.date(2026, 8, 28)


@pytest.fixture
def project(
    messy_project_plan: bytes,
    clean_resources: bytes,
    clean_budget: bytes,
    risks_book: bytes,
) -> ProjectData:
    return ProjectData(
        project_name="Project X",
        as_of=AS_OF,
        tasks=parse_workbook(messy_project_plan, load_mapping("project_plan")).rows,  # type: ignore[arg-type]
        resources=parse_workbook(clean_resources, load_mapping("resources")).rows,  # type: ignore[arg-type]
        budget=parse_workbook(clean_budget, load_mapping("budget")).rows,  # type: ignore[arg-type]
        risks=parse_workbook(risks_book, load_mapping("risks")).rows,  # type: ignore[arg-type]
    )


class TestEndToEnd:
    def test_overall_is_orange_for_this_project(self, project: ProjectData) -> None:
        assert compute_health(project).overall is HealthStatus.ORANGE

    def test_dimension_statuses(self, project: ProjectData) -> None:
        result = compute_health(project)
        actual = {d.dimension: d.status for d in result.dimensions}
        assert actual == {
            HealthDimension.SCHEDULE: HealthStatus.RED,
            HealthDimension.BUDGET: HealthStatus.YELLOW,
            HealthDimension.RESOURCES: HealthStatus.ORANGE,
            HealthDimension.DEPENDENCIES: HealthStatus.RED,
            # Sin fuente de datos en el contrato canónico: UNKNOWN, no GREEN.
            HealthDimension.SCOPE: HealthStatus.UNKNOWN,
            HealthDimension.QUALITY: HealthStatus.UNKNOWN,
            HealthDimension.CUSTOMER: HealthStatus.UNKNOWN,
        }

    def test_every_reason_carries_evidence(self, project: ProjectData) -> None:
        """Ningún número sin procedencia (regla 3 del README)."""
        ledger = EvidenceLedger()
        result = compute_health(project, ledger)
        assert result.all_reasons
        for reason in result.all_reasons:
            assert ledger.get(reason.evidence.evidence_id) is not None
            assert reason.evidence.claim_type is ClaimType.FACT

    def test_schedule_reasons_are_specific(self, project: ProjectData) -> None:
        schedule = compute_health(project).dimension(HealthDimension.SCHEDULE)
        assert schedule is not None
        texts = " · ".join(r.text for r in schedule.reasons)
        assert "4 tareas críticas retrasadas" in texts
        assert "UAT start" in texts

    def test_evidence_cites_the_source_file_and_range(self, project: ProjectData) -> None:
        schedule = compute_health(project).dimension(HealthDimension.SCHEDULE)
        assert schedule is not None
        assert schedule.reasons[0].evidence.citation() == "Project Plan.xlsx!Tasks"

    def test_result_records_the_rules_version(self, project: ProjectData) -> None:
        assert compute_health(project).rules_version == load_rules()["version"]

    def test_is_deterministic(self, project: ProjectData) -> None:
        """ADR-005: la misma entrada produce siempre la misma salida."""
        first = compute_health(project)
        second = compute_health(project)
        assert first.overall is second.overall
        assert [d.status for d in first.dimensions] == [d.status for d in second.dimensions]


class TestUnknownIsNotGreen:
    def test_empty_project_is_unknown_not_green(self) -> None:
        result = compute_health(ProjectData(project_name="Vacío", as_of=AS_OF))
        assert result.overall is HealthStatus.UNKNOWN
        assert all(d.status is HealthStatus.UNKNOWN for d in result.dimensions)

    def test_unknown_dimension_explains_itself(self) -> None:
        result = compute_health(ProjectData(project_name="Vacío", as_of=AS_OF))
        scope = result.dimension(HealthDimension.SCOPE)
        assert scope is not None
        assert "UNKNOWN en lugar de asumir que va bien" in scope.reasons[0].text


class TestAggregation:
    """El Overall no puede ocultar una dimensión en rojo."""

    def _dim(self, name: HealthDimension, status: HealthStatus) -> DimensionResult:
        return DimensionResult(name, status, ())

    def test_a_red_dimension_floors_the_overall_at_orange(self) -> None:
        dimensions = [
            self._dim(HealthDimension.SCHEDULE, HealthStatus.RED),
            self._dim(HealthDimension.BUDGET, HealthStatus.GREEN),
            self._dim(HealthDimension.RESOURCES, HealthStatus.GREEN),
            self._dim(HealthDimension.DEPENDENCIES, HealthStatus.GREEN),
            self._dim(HealthDimension.SCOPE, HealthStatus.GREEN),
            self._dim(HealthDimension.QUALITY, HealthStatus.GREEN),
            self._dim(HealthDimension.CUSTOMER, HealthStatus.GREEN),
        ]
        # Una media ponderada daría GREEN (0,9/1,0 ≈ 1). La regla del peor caso
        # lo impide: el Overall queda como mucho un nivel por debajo del peor.
        assert _aggregate(dimensions, load_rules()) is HealthStatus.ORANGE

    def test_all_green_stays_green(self) -> None:
        dimensions = [self._dim(d, HealthStatus.GREEN) for d in HealthDimension]
        assert _aggregate(dimensions, load_rules()) is HealthStatus.GREEN

    def test_too_many_unknowns_makes_overall_unknown(self) -> None:
        dimensions = [
            self._dim(HealthDimension.SCHEDULE, HealthStatus.GREEN),
            self._dim(HealthDimension.BUDGET, HealthStatus.GREEN),
            self._dim(HealthDimension.RESOURCES, HealthStatus.UNKNOWN),
            self._dim(HealthDimension.DEPENDENCIES, HealthStatus.UNKNOWN),
            self._dim(HealthDimension.SCOPE, HealthStatus.UNKNOWN),
            self._dim(HealthDimension.QUALITY, HealthStatus.UNKNOWN),
            self._dim(HealthDimension.CUSTOMER, HealthStatus.UNKNOWN),
        ]
        assert _aggregate(dimensions, load_rules()) is HealthStatus.UNKNOWN


class TestScheduleEdgeCases:
    def test_closed_late_tasks_do_not_count_as_currently_late(self) -> None:
        data = ProjectData(
            project_name="P",
            as_of=AS_OF,
            tasks=(
                TaskRow(
                    task_id="T-1", task="cerrada tarde", status=TaskStatus.DONE,
                    planned_end=dt.date(2026, 1, 1), actual_end=dt.date(2026, 3, 1),
                    critical=True,
                ),
            ),
        )
        schedule = compute_health(data).dimension(HealthDimension.SCHEDULE)
        assert schedule is not None
        assert schedule.status is HealthStatus.GREEN

    def test_reasons_are_empty_when_nothing_is_wrong(self) -> None:
        data = ProjectData(
            project_name="P",
            as_of=AS_OF,
            tasks=(
                TaskRow(
                    task_id="T-1", task="a tiempo", status=TaskStatus.IN_PROGRESS,
                    planned_end=dt.date(2026, 12, 1),
                ),
            ),
        )
        schedule = compute_health(data).dimension(HealthDimension.SCHEDULE)
        assert schedule is not None
        assert schedule.status is HealthStatus.GREEN
        assert schedule.reasons == ()


class TestEvidenceLedger:
    def test_ids_are_unique_and_resolvable(self) -> None:
        ledger = EvidenceLedger()
        first = ledger.fact_from_excel("a", document="X.xlsx", locator="A1")
        second = ledger.fact_from_excel("b", document="X.xlsx", locator="A2")
        assert first.evidence_id != second.evidence_id
        assert ledger.subset([first.evidence_id, "ev_9999"]) == (first,)
        assert len(ledger) == 2

    def test_unknown_id_is_not_resolvable(self) -> None:
        """Base del validador de salida: una cita inventada no existe."""
        assert EvidenceLedger().get("ev_0001") is None


def test_reason_is_immutable() -> None:
    reason = Reason("x", EvidenceLedger().fact_from_excel("s", document="d", locator="l"))
    with pytest.raises(AttributeError):
        reason.text = "otro"  # type: ignore[misc]


class TestDataQualityGate:
    """Una fuente con demasiadas filas en cuarentena no produce un Health verde."""

    def test_unreliable_source_makes_its_dimensions_unknown(
        self, project: ProjectData
    ) -> None:
        degraded = ProjectData(
            project_name=project.project_name,
            as_of=project.as_of,
            tasks=project.tasks,
            risks=project.risks,
            resources=project.resources,
            budget=project.budget,
            unreliable_sources=frozenset({"project_plan"}),
        )
        result = compute_health(degraded)
        assert result.dimension(HealthDimension.SCHEDULE).status is HealthStatus.UNKNOWN  # type: ignore[union-attr]
        assert result.dimension(HealthDimension.DEPENDENCIES).status is HealthStatus.UNKNOWN  # type: ignore[union-attr]
        assert result.dimension(HealthDimension.BUDGET).status is HealthStatus.UNKNOWN  # type: ignore[union-attr]
        # Recursos viene de otro fichero: sigue calculándose.
        assert result.dimension(HealthDimension.RESOURCES).status is HealthStatus.ORANGE  # type: ignore[union-attr]

    def test_it_says_why_instead_of_going_green(self, project: ProjectData) -> None:
        degraded = ProjectData(
            project_name=project.project_name,
            as_of=project.as_of,
            tasks=project.tasks,
            unreliable_sources=frozenset({"project_plan"}),
        )
        schedule = compute_health(degraded).dimension(HealthDimension.SCHEDULE)
        assert schedule is not None
        assert "demasiadas filas en cuarentena" in schedule.reasons[0].text

    def test_overall_goes_unknown_when_most_sources_are_bad(
        self, project: ProjectData
    ) -> None:
        degraded = ProjectData(
            project_name=project.project_name,
            as_of=project.as_of,
            tasks=project.tasks,
            resources=project.resources,
            budget=project.budget,
            unreliable_sources=frozenset({"project_plan", "resources", "budget"}),
        )
        assert compute_health(degraded).overall is HealthStatus.UNKNOWN
