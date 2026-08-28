# 02 — Arquitectura

---

## 1. Vista general

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  NAVEGADOR                                                                   │
│  Next.js + MSAL.js (Authorization Code + PKCE)                               │
│  Dashboard · Chat · Detalle de proyecto · What-If                            │
└───────────────────────────────┬──────────────────────────────────────────────┘
                                │ 1. login  ┌─────────────────────────────────┐
                                ├──────────►│  MICROSOFT ENTRA ID             │
                                │           │  App SPA + App API (2 registros)│
                                │◄──────────┤  access_token (scope: api://…)  │
                                │           └─────────────────────────────────┘
                                │ 2. Bearer token
┌───────────────────────────────▼──────────────────────────────────────────────┐
│  BACKEND — FastAPI (Python 3.12)                                             │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │  CAPA 0 · SEGURIDAD  (todo pasa por aquí, sin excepción)                │  │
│  │  · Validación JWT (firma, aud, iss, exp, scp)                           │  │
│  │  · UserPrincipal (oid, tid, upn)                                        │  │
│  │  · Authorization: ¿este usuario puede ver este project_id?              │  │
│  │  · Audit log de toda consulta y de todo documento devuelto              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│           │                          │                        │              │
│  ┌────────▼────────┐   ┌─────────────▼──────────┐   ┌─────────▼───────────┐  │
│  │ INGESTA         │   │ INTELIGENCIA           │   │ API REST            │  │
│  │ · delta sync    │   │ · Health engine (reglas)│   │ /projects           │  │
│  │ · descarga      │   │ · Early Warning (series)│   │ /health             │  │
│  │ · parseo Excel  │   │ · Predictor (baseline→ML)│  │ /prediction         │  │
│  │ · parseo docs   │   │ · What-If (simulación)  │   │ /warnings           │  │
│  │ · validación    │   │ · RAG orchestrator      │   │ /ask                │  │
│  │ · chunk+embed   │   │ · Evidence Ledger       │   │ /ingest             │  │
│  └────────┬────────┘   └─────────────┬──────────┘   └─────────────────────┘  │
└───────────┼──────────────────────────┼───────────────────────────────────────┘
            │ OBO token                │
┌───────────▼────────────┐   ┌─────────▼──────────────┐   ┌───────────────────┐
│  MICROSOFT GRAPH       │   │  PostgreSQL + pgvector │   │  LLM (OpenAI /    │
│  /sites /drives /items │   │  · datos de proyecto   │   │  Azure OpenAI)    │
│  /copilot/retrieval    │   │  · snapshots           │   │  Responses API    │
│  (si hay licencia)     │   │  · chunks + embeddings │   │  Structured Output│
└────────────────────────┘   │  · evidencias, audit   │   └───────────────────┘
                             └────────────────────────┘
```

---

## 2. Decisiones estructurales

### 2.1 · La autorización ocurre antes del LLM, siempre

```
Petición ──► Validar JWT ──► Resolver proyectos autorizados ──► Filtrar ──► Recuperar ──► LLM
                                        ▲
                            aquí termina la seguridad;
                            el LLM ya solo ve datos permitidos
```

El modelo **nunca** recibe un identificador de proyecto que no haya sido validado, y **nunca**
tiene una herramienta capaz de ampliar su propio alcance. Aunque alucine un `project_id`,
la herramienta lo rechaza con 403 antes de tocar la base de datos.

### 2.2 · Herramientas tipadas y con alcance fijado (tool calling)

El LLM no consulta la base de datos ni escribe SQL. Dispone de un catálogo cerrado de
funciones, todas con el `user` inyectado por el backend (no por el modelo):

| Herramienta | Devuelve | Tipo de dato |
| --- | --- | --- |
| `get_project_health(project_id)` | Health por dimensión + razones | `FACT` |
| `get_delay_prediction(project_id)` | Probabilidad, rango de días, factores | `PREDICTION` |
| `list_delayed_tasks(project_id)` | Tareas con desviación | `FACT` |
| `list_risks(project_id)` | Riesgos del registro | `FACT` |
| `list_early_warnings(project_id)` | Señales tempranas activas | `FACT` |
| `get_metric_trend(project_id, metric, weeks)` | Serie temporal | `FACT` |
| `search_documents(project_id, query)` | Extractos con cita | `FACT` (cita) |
| `find_similar_projects(project_id)` | Proyectos históricos parecidos | `INFERENCE` |

Ninguna herramienta escribe. Ninguna herramienta accede a la red exterior. Esto elimina la
vía principal de exfiltración por inyección de prompt.

### 2.3 · Evidence Ledger — el mecanismo de trazabilidad

Cada dato que el sistema muestra se registra como una evidencia con identificador propio:

```json
{
  "evidence_id": "ev_01J8X...",
  "claim_type": "FACT",
  "source_system": "sharepoint",
  "source_kind": "excel",
  "document": "Project Plan.xlsx",
  "locator": "Tasks!A15:H15",
  "document_path": "/sites/Projects/Client A/Project X/Project Plan.xlsx",
  "modified_at": "2026-08-21T09:14:00Z",
  "author": "…",
  "extracted_at": "2026-08-27T22:03:11Z",
  "value": {"task": "Integration test", "planned_end": "2026-08-18", "status": "Blocked"}
}
```

Para predicciones, `source_system` es `ml_model` y se guardan `model_id`, `model_version`,
`features_hash` y las contribuciones SHAP. Para conclusiones del LLM, `INFERENCE`, con la
lista de `evidence_id` de las que se derivó.

**Validación de salida (el control anti-alucinación).** El LLM responde con *structured
output* obligatorio:

```json
{
  "statements": [
    {"text": "7 tareas críticas están retrasadas",
     "claim_type": "FACT", "evidence_ids": ["ev_01J8X..."]},
    {"text": "La probabilidad de retraso es del 68 %",
     "claim_type": "PREDICTION", "evidence_ids": ["ev_ml_0042"]},
    {"text": "El retraso parece concentrarse en la integración",
     "claim_type": "INFERENCE", "evidence_ids": ["ev_01J8X...", "ev_01J9A..."]}
  ]
}
```

El backend **verifica cada afirmación antes de mostrarla**:
1. ¿Todos los `evidence_ids` existen en el ledger de esta conversación? Si no → se descarta.
2. ¿Un `FACT` sin evidencia? → se descarta.
3. ¿Un número en el texto que no aparece en ninguna evidencia citada? → se marca para revisión.

Una afirmación descartada no se muestra. Si no queda nada, el sistema responde
**"no dispongo de información suficiente"**, que es la respuesta correcta.

### 2.4 · Los números no los produce el LLM

| Salida | Origen | ¿Reproducible? |
| --- | --- | --- |
| Overall Health: ORANGE | Motor de reglas (Python puro) | Sí, determinista |
| Schedule: RED — 7 tareas retrasadas | Consulta SQL sobre `task` | Sí |
| Delay probability: 68 % | Modelo (reglas calibradas → ML) | Sí, con `model_version` |
| Estimated delay: 7–12 días | Intervalo del modelo | Sí |
| "El riesgo subió por bloqueos" | LLM, a partir de lo anterior | No, pero es solo redacción |

---

## 3. Flujo completo: "Analiza el proyecto Project X"

```
 1. POST /ask                          Bearer <token de usuario>
 2. Validar JWT ..................... oid, tid, scp
 3. Resolver "Project X" ............ project registry → project_id (o error si no autorizado)
 4. Comprobar autorización .......... ¿este oid tiene acceso a este project_id? → si no, 403
 5. ¿Datos frescos? ................. si el último ingest > N horas → lanzar ingesta incremental
 6. Cargar datos duros .............. task, risk, resource, budget, milestone, dependency
 7. Health engine ................... 8 dimensiones + razones     → evidencias FACT
 8. Predictor ....................... prob. retraso + rango + SHAP → evidencia PREDICTION
 9. Early Warning ................... tendencias sobre snapshots   → evidencias FACT
10. RetrievalProvider.search() ...... extractos de documentos      → evidencias FACT (citas)
11. Verificar acceso de cada cita ... Graph GET item con token del usuario → descartar 403/404
12. Construir prompt ............... system (política) + tools + evidencias delimitadas
13. LLM (Responses API) ............ structured output obligatorio
14. Validar afirmaciones ........... descartar lo no fundamentado
15. Audit log ...................... quién, qué, qué documentos, qué modelo, qué versión
16. Respuesta ...................... texto + fuentes + etiquetas de tipo de dato
```

---

## 4. Pipeline de ingesta

```
        ┌── Excel (.xlsx) ────────────────────────────────────────────────┐
        │                                                                 │
Graph   │  GET /drives/{id}/root/delta          (qué cambió)              │
delta ──┤  GET /drives/{id}/items/{id}/content  (descarga, solo lectura)  │
        │  openpyxl read_only                   (parseo)                  │
        │  schema mapping YAML                  (fichero → campos canónicos)│
        │  Pydantic                             (validación fila a fila)  │
        │  → tablas: task, risk, resource, budget_entry, milestone        │
        │  → filas inválidas: tabla de cuarentena con motivo              │
        │  → informe de calidad de datos                                  │
        └─────────────────────────────────────────────────────────────────┘

        ┌── Documentos (.docx / .pdf / .pptx / .md) ──────────────────────┐
        │  descarga → extracción de texto (python-docx / pypdf)           │
        │  chunking 800–1000 tokens, solape 15 %, respetando encabezados  │
        │  metadata por chunk (ver abajo)                                 │
        │  hash SHA-256 → si no cambió, no se vuelve a embeber            │
        │  embeddings → pgvector                                          │
        └─────────────────────────────────────────────────────────────────┘

        ┌── Snapshot semanal ─────────────────────────────────────────────┐
        │  ~30 métricas agregadas por proyecto, inmutable, idempotente    │
        │  clave: (project_id, iso_week) — base de Early Warning y de ML  │
        └─────────────────────────────────────────────────────────────────┘
```

### Metadata obligatoria de cada chunk

```yaml
tenant_id:        # aislamiento multi-tenant desde el día 1
project_id:       # filtro primario de acceso
client_id:
site_id:          # SharePoint site
drive_id:
item_id:          # driveItem — permite reverificar acceso vía Graph
document_name:
document_path:
page_or_section:  # para citar con precisión
modified_at:      # detección de obsolescencia
author:
source_system:    sharepoint | onedrive
sensitivity_label:# etiqueta de Purview, si existe
content_hash:     # SHA-256, evita reprocesar
ingested_at:
injection_flag:   # true si el detector encontró patrones de inyección
```

`item_id` es el campo que hace posible la reverificación de acceso de P1. Sin él, el índice
no se puede auditar.

---

## 5. Modelo de datos (resumen)

| Tabla | Propósito | Nota |
| --- | --- | --- |
| `tenant` | Aislamiento | Presente desde el día 1 aunque haya uno solo |
| `app_user` | Usuario (oid de Entra) | Nunca se guarda contraseña ni token en claro |
| `project` | Registro canónico de proyecto | Cliente, tecnología, PM, sitio, carpeta |
| `project_access` | Qué usuario ve qué proyecto | Derivado de Graph, con caducidad |
| `project_source` | driveItem vigilado | `delta_link`, `content_hash` |
| `task` | Plan de proyecto | Origen: `Project Plan.xlsx` |
| `risk` | Registro de riesgos | Origen: `Risks.xlsx` |
| `resource_allocation` | Asignación y disponibilidad | Origen: `Resources.xlsx` |
| `budget_entry` | Presupuesto y consumo | Origen: `Budget.xlsx` |
| `milestone`, `dependency`, `incident`, `scope_change` | Señales de Health y EW | |
| `quarantined_row` | Filas que no validaron | Con motivo. Alimenta el informe de calidad |
| `document`, `document_chunk` | RAG | `chunk.embedding vector(1536)` |
| `project_snapshot` | **Foto semanal inmutable** | Base de Early Warning y del dataset de ML |
| `health_result` | Health calculado, con versión de reglas | Auditable |
| `prediction` | Predicción con `model_version` y SHAP | Auditable |
| `evidence` | Evidence Ledger | Corazón de la trazabilidad |
| `alert`, `alert_history` | Early Warning enviado | Dedup y cooldown |
| `audit_log` | Quién preguntó qué y qué se devolvió | **Sin contenido de documentos** |
| `ingestion_run` | Trazabilidad de cada ingesta | Métricas de calidad |

---

## 6. Despliegue

### PoC (1 usuario) — todo local

```
docker compose up
  ├── postgres:16 + pgvector          localhost:5432
  ├── api        (FastAPI, uvicorn)   localhost:8000
  └── web        (Next.js)            localhost:3000   ← redirect URI de Entra
```

Sin Azure. Sin datos en reposo fuera del portátil corporativo (cifrado por BitLocker/FileVault
según la política de la empresa). Es la configuración más fácil de aprobar por Security para
una prueba.

### Producción (Fase 3) — Azure

```
Azure Container Apps        api + web (identidad administrada)
Azure Database for PostgreSQL Flexible Server + pgvector (+ pg_diskann si crece)
Azure Key Vault             secretos y claves
Azure Monitor / App Insights logs y métricas (sin contenido de documentos)
Azure OpenAI (DataZone EU)  o OpenAI Platform empresarial
```

`pg_diskann` está disponible en Azure Database for PostgreSQL Flexible Server y soporta
vectores de hasta 16.000 dimensiones con cuantización activada
([doc](https://learn.microsoft.com/azure/postgresql/extensions/how-to-use-pgdiskann)),
lo cual deja abierta la puerta a `text-embedding-3-large` a 3072 dimensiones sin cambiar de
motor. Para el PoC, HNSW de pgvector es más que suficiente.

---

## 7. Observabilidad

- **Logs estructurados** (JSON, `structlog`) con `request_id`, `user_oid`, `project_id`,
  `tool`, `latency_ms`, `token_usage`. **Nunca** contenido de documentos ni prompts completos.
- **Audit log** en base de datos, separado de los logs de aplicación, con retención propia.
- **Métricas**: latencia p95 por endpoint, tasa de 429 de Graph, coste de LLM por consulta,
  % de filas en cuarentena por ingesta, tasa de afirmaciones descartadas por el validador
  (indicador directo de alucinación).
