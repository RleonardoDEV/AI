from __future__ import annotations

import datetime as dt

import pytest

from app.ingestion.excel.mapping import (
    SchemaMappingError,
    available_mappings,
    load_mapping,
)
from app.ingestion.excel.parser import parse_workbook
from app.schemas.domain import TaskRow, TaskStatus


class TestMappings:
    def test_all_shipped_mappings_load(self) -> None:
        assert set(available_mappings()) == {"budget", "project_plan", "resources", "risks"}
        for name in available_mappings():
            mapping = load_mapping(name)
            assert mapping.columns
            assert mapping.required_columns

    def test_unknown_mapping_lists_alternatives(self) -> None:
        with pytest.raises(SchemaMappingError, match="Disponibles"):
            load_mapping("no_existe")


class TestHeaderDetection:
    def test_finds_header_below_logo_and_metadata(self, messy_project_plan: bytes) -> None:
        """La cabecera real está en la fila 7, no en la 1."""
        result = parse_workbook(messy_project_plan, load_mapping("project_plan"))
        assert result.header_row == 7
        assert result.sheet_name == "Tareas"

    def test_resolves_sheet_and_columns_by_alias(self, messy_project_plan: bytes) -> None:
        result = parse_workbook(messy_project_plan, load_mapping("project_plan"))
        # "Fin Planificado", "Estado" y "Horas Reales" se mapean por alias.
        assert {"task_id", "planned_end", "status", "actual_hours"} <= set(result.column_map)

    def test_reports_columns_it_could_not_map(self, messy_project_plan: bytes) -> None:
        result = parse_workbook(messy_project_plan, load_mapping("project_plan"))
        assert "Comentarios" in result.unmapped_headers
        assert "actual_start" in result.missing_columns


class TestRowParsing:
    @pytest.fixture
    def result(self, messy_project_plan: bytes):  # noqa: ANN201
        return parse_workbook(messy_project_plan, load_mapping("project_plan"))

    def test_valid_rows_are_parsed(self, result) -> None:  # noqa: ANN001
        ids = {t.task_id for t in result.rows}
        assert ids == {"T-001", "T-002", "T-003", "T-004", "T-005"}

    def test_text_dates_are_coerced(self, result) -> None:  # noqa: ANN001
        task = next(t for t in result.rows if t.task_id == "T-002")
        assert task.planned_end == dt.date(2026, 7, 25)

    def test_status_synonyms_normalised(self, result) -> None:  # noqa: ANN001
        by_id = {t.task_id: t for t in result.rows}
        assert by_id["T-003"].status is TaskStatus.BLOCKED   # "Blocked"
        assert by_id["T-004"].status is TaskStatus.BLOCKED   # "on hold"
        assert by_id["T-001"].status is TaskStatus.DONE      # "Completada"

    def test_booleans_in_two_languages(self, result) -> None:  # noqa: ANN001
        by_id = {t.task_id: t for t in result.rows}
        assert by_id["T-005"].milestone is True   # "Sí"
        assert by_id["T-003"].milestone is False  # "NO"
        assert by_id["T-003"].critical is True    # "SI"

    def test_dependencies_parsed_as_list(self, result) -> None:  # noqa: ANN001
        by_id = {t.task_id: t for t in result.rows}
        assert by_id["T-004"].depends_on == ("T-003",)


class TestQuarantine:
    @pytest.fixture
    def result(self, messy_project_plan: bytes):  # noqa: ANN201
        return parse_workbook(messy_project_plan, load_mapping("project_plan"))

    def test_nothing_is_dropped_silently(self, result) -> None:  # noqa: ANN001
        """Toda fila problemática queda registrada con su motivo."""
        assert result.reasons() == {
            "missing_required": 1,      # T-008 sin fecha de fin planificada
            "probable_subtotal_row": 1, # fila TOTAL
            "unknown_status": 1,        # T-006 "Semi-hecho"
            "unparseable_date": 1,      # T-007 "cuando se pueda"
        }

    def test_blank_rows_are_not_errors(self, result) -> None:  # noqa: ANN001
        assert result.total_rows == 9  # 5 válidas + 4 en cuarentena; la vacía no cuenta

    def test_quarantine_points_at_the_offending_row(self, result) -> None:  # noqa: ANN001
        bad_date = next(q for q in result.quarantined if q.reason == "unparseable_date")
        assert bad_date.field_name == "planned_end"
        assert bad_date.raw_value == "cuando se pueda"
        assert bad_date.row_number == 14

    def test_ratio_is_reported(self, result) -> None:  # noqa: ANN001
        assert result.quarantine_ratio == pytest.approx(4 / 9)


class TestStaleFormulas:
    def test_formula_without_cached_value_gets_its_own_reason(
        self, plan_with_stale_formula: bytes
    ) -> None:
        """Distinguir "celda vacía" de "fórmula sin recalcular" (docs/00, P3).

        openpyxl no evalúa fórmulas: lee el último valor cacheado por Excel. Si
        no lo hay, se reporta como incidencia de calidad en lugar de tratarse
        como un hueco cualquiera.
        """
        result = parse_workbook(plan_with_stale_formula, load_mapping("project_plan"))
        assert len(result.rows) == 1
        assert result.reasons() == {"formula_without_cached_value": 1}
        problem = result.quarantined[0]
        assert problem.field_name == "planned_end"
        assert "recalcule" in (problem.detail or "")


class TestOtherWorkbooks:
    def test_resources(self, clean_resources: bytes) -> None:
        result = parse_workbook(clean_resources, load_mapping("resources"))
        assert not result.quarantined
        carla = next(r for r in result.rows if r.resource == "Carla")
        assert carla.allocation_pct == 120
        assert carla.key_resource is True
        assert carla.absence_days == 5

    def test_budget(self, clean_budget: bytes) -> None:
        result = parse_workbook(clean_budget, load_mapping("budget"))
        assert len(result.rows) == 2
        assert sum(b.actual_amount or 0 for b in result.rows) == 171000

    def test_risks(self, risks_book: bytes) -> None:
        result = parse_workbook(risks_book, load_mapping("risks"))
        assert len(result.rows) == 3
        top = max(result.rows, key=lambda r: r.severity_score)
        assert top.risk_id == "R-01"
        assert top.severity_score == 9
        assert sum(1 for r in result.rows if r.is_open) == 2


class TestMismatchedFile:
    def test_wrong_template_fails_loudly(self, clean_budget: bytes) -> None:
        """Un fichero que no encaja con el contrato no se parsea a medias."""
        with pytest.raises(SchemaMappingError, match="fila de cabecera"):
            parse_workbook(clean_budget, load_mapping("project_plan"))


class TestDomainLogic:
    def test_days_late_uses_actual_end_for_closed_tasks(self) -> None:
        closed = TaskRow(
            task_id="T-1", task="x", status=TaskStatus.DONE,
            planned_end=dt.date(2026, 6, 20), actual_end=dt.date(2026, 6, 28),
        )
        # 8 días tarde, independientemente de la fecha de referencia
        assert closed.days_late(dt.date(2026, 12, 31)) == 8

    def test_days_late_uses_reference_date_for_open_tasks(self) -> None:
        open_task = TaskRow(
            task_id="T-2", task="x", status=TaskStatus.IN_PROGRESS,
            planned_end=dt.date(2026, 8, 18),
        )
        assert open_task.days_late(dt.date(2026, 8, 28)) == 10
        assert open_task.days_late(dt.date(2026, 8, 1)) == 0

    def test_no_planned_end_means_no_measurable_delay(self) -> None:
        task = TaskRow(task_id="T-3", task="x", status=TaskStatus.IN_PROGRESS)
        assert task.days_late(dt.date(2026, 8, 28)) == 0
