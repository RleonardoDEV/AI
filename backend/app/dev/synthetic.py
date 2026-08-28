"""DATOS SINTÉTICOS — NO SON DATOS REALES DE NINGÚN PROYECTO.

Sirven para probar que el código funciona de extremo a extremo antes de tener
acceso a SharePoint. No sirven para afirmar nada sobre proyectos reales, y
ningún modelo entrenado con ellos puede desplegarse en producción
(docs/05 §3.5).

Los ficheros generados imitan a propósito el desorden de un plan de proyecto
real: cabecera desplazada, fechas como texto, filas de subtotal y estados sin
normalizar.
"""

from __future__ import annotations

import datetime as dt
import io

from openpyxl import Workbook

IS_SYNTHETIC = True

_PLAN_ROWS = [
    ("T-001", "Análisis funcional", "Ana", dt.datetime(2026, 6, 1), dt.datetime(2026, 6, 20),
     dt.datetime(2026, 6, 28), "Completada", 80, 96, "No", "", "Sí"),
    ("T-002", "Diseño técnico", "Beto", "01/07/2026", "25/07/2026",
     None, "En curso", 120, 140, "No", "T-001", "Sí"),
    ("T-003", "Integración con ERP", "Carla", dt.datetime(2026, 7, 1), dt.datetime(2026, 8, 10),
     None, "Blocked", 160, 60, "No", "T-002", "Sí"),
    ("T-004", "Pruebas de integración", "Dani", dt.datetime(2026, 8, 1), dt.datetime(2026, 8, 18),
     None, "on hold", 80, 20, "No", "T-003", "Sí"),
    ("T-005", "UAT start", "Ana", dt.datetime(2026, 8, 15), dt.datetime(2026, 8, 18),
     None, "Pendiente", 0, 0, "Sí", "T-004", "Sí"),
    ("T-006", "Formación", "Beto", dt.datetime(2026, 9, 1), dt.datetime(2026, 9, 5),
     None, "Semi-hecho", 16, 0, "No", "", "No"),
    ("T-007", "Documentación", "Carla", None, "cuando se pueda",
     None, "Pendiente", 24, 0, "No", "", "No"),
    ("T-008", "Preparación de entornos", "Ana", dt.datetime(2026, 5, 1), dt.datetime(2026, 5, 15),
     dt.datetime(2026, 5, 14), "Completada", 40, 38, "No", "", "No"),
    ("T-009", "Migración de datos", "Beto", dt.datetime(2026, 7, 10), dt.datetime(2026, 8, 30),
     None, "En curso", 100, 45, "No", "T-002", "No"),
    ("T-010", "Configuración de workflows", "Carla", dt.datetime(2026, 7, 15),
     dt.datetime(2026, 9, 10),
     None, "En curso", 90, 30, "No", "T-002", "No"),
    ("T-011", "Informe de diseño", "Dani", dt.datetime(2026, 6, 5), dt.datetime(2026, 6, 25),
     dt.datetime(2026, 6, 24), "Completada", 30, 28, "No", "T-001", "No"),
    ("T-012", "Plan de pruebas", "Ana", dt.datetime(2026, 8, 1), dt.datetime(2026, 9, 15),
     None, "Pendiente", 20, 0, "No", "T-004", "No"),
    ("T-013", "Revisión de seguridad", "Beto", dt.datetime(2026, 9, 1), dt.datetime(2026, 9, 20),
     None, "Pendiente", 24, 0, "No", "", "No"),
    ("T-014", "Go-live", "Ana", dt.datetime(2026, 10, 1), dt.datetime(2026, 10, 5),
     None, "Pendiente", 16, 0, "Sí", "T-005", "Sí"),
    ("T-015", "Cierre de proyecto", "Ana", dt.datetime(2026, 10, 10), dt.datetime(2026, 10, 20),
     None, "Pendiente", 8, 0, "Sí", "T-014", "No"),
    ("T-016", "Soporte post go-live", "Dani", dt.datetime(2026, 10, 6), dt.datetime(2026, 11, 6),
     None, "Pendiente", 60, 0, "No", "T-014", "No"),
    (None, None, None, None, None, None, None, 480, 316, None, None, None),
]


def _save(workbook: Workbook) -> bytes:
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


def project_plan() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Tareas"
    ws["A1"] = "[SINTÉTICO] Consultoría de ejemplo"
    ws["A2"] = "Project Plan — Project X"
    ws["A4"] = "Cliente:"
    ws["B4"] = "Client A"
    ws.append([])
    ws.append([])
    header = ["Task ID", "Tarea", "Owner", "Planned Start", "Fin Planificado", "Actual End",
              "Estado", "Estimated Hours", "Horas Reales", "Hito", "Depends On", "Critica"]
    for column, value in enumerate(header, start=1):
        ws.cell(row=7, column=column, value=value)
    for row in _PLAN_ROWS:
        ws.append(list(row))
    return _save(wb)


def risks() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Riesgos"
    ws.append(["Risk ID", "Descripcion", "Probabilidad", "Impacto", "Estado", "Responsable"])
    ws.append(["R-01", "Dependencia de integración externa", "Alta", "Alto", "Abierto", "Ana"])
    ws.append(["R-02", "Disponibilidad del Tech Lead", "Media", "Alto", "Mitigando", "Ana"])
    ws.append(["R-03", "Cambio de alcance del cliente", "Baja", "Medio", "Cerrado", "Beto"])
    return _save(wb)


def resources() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Recursos"
    ws.append(["Recurso", "Rol", "Dedicacion", "Dias Ausencia", "Recurso Clave"])
    ws.append(["Ana", "Analista", 100, 0, "No"])
    ws.append(["Beto", "Developer", 80, 0, "No"])
    ws.append(["Carla", "Tech Lead", 120, 5, "Sí"])
    ws.append(["Dani", "Developer", 70, 0, "No"])
    return _save(wb)


def budget() -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Presupuesto"
    ws.append(["Concepto", "Importe Planificado", "Importe Real", "Moneda"])
    ws.append(["Desarrollo", 120000, 141000, "EUR"])
    ws.append(["Licencias", 30000, 30000, "EUR"])
    return _save(wb)


WORKBOOKS = {
    "project_plan": project_plan,
    "risks": risks,
    "resources": resources,
    "budget": budget,
}
