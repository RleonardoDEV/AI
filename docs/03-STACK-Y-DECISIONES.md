# 03 — Stack tecnológico y registro de decisiones

---

## 1. Stack propuesto

| Capa | Elección | Por qué |
| --- | --- | --- |
| Backend | **Python 3.12 + FastAPI** | Tipado con Pydantic v2, async nativo, OpenAPI automático, mismo lenguaje que el ML |
| Validación | **Pydantic v2** | Contratos de datos explícitos en ingesta, API y salida del LLM |
| ORM / migraciones | **SQLAlchemy 2.0 + Alembic** | Tipado, y migraciones versionadas desde el primer día |
| HTTP | **httpx** | Async, timeouts y reintentos correctos contra Graph |
| Identidad | **MSAL for Python** | Librería oficial de Microsoft; implementa OBO (`acquire_token_on_behalf_of`) |
| Excel | **openpyxl** (`read_only=True`) | Lectura pura, sin permisos de escritura (ver ADR-004) |
| Word / PDF | **python-docx**, **pypdf** | Extracción de texto sin dependencias pesadas |
| Base de datos | **PostgreSQL 16** | Una sola tecnología para datos relacionales y vectores |
| Vectores | **pgvector** (HNSW) | Sin servicio adicional que asegurar. Migrable a Azure AI Search |
| LLM | **OpenAI Responses API** *o* **Azure OpenAI**, tras `LLMClient` | Decisión abierta (`docs/08`); se abstrae para no bloquear |
| ML | **scikit-learn** → **LightGBM** + **SHAP** | Adecuado al tamaño de datos (ver `docs/05`) |
| Frontend | **Next.js (App Router) + TypeScript** | SSR, MSAL React maduro, buen ecosistema |
| Gráficos | **Recharts** | Suficiente para un dashboard que se lee en < 1 minuto |
| Logs | **structlog** | JSON estructurado, filtrable, sin contenido sensible |
| Tests | **pytest** + **pytest-asyncio** + **respx** | Graph y LLM mockeados; sin llamadas reales en CI |
| Contenedores | **Docker + docker compose** | Un comando para levantar el PoC completo |
| Calidad | **ruff**, **mypy --strict**, **pre-commit** | Tipado estricto en un proyecto donde los errores silenciosos son caros |

---

## 2. Registro de decisiones (ADR)

### ADR-001 · Aplicación propia con puerta a integración en Copilot
**Decisión.** Construir el motor propio (Opción B) manteniendo la posibilidad de exponerlo
como agente de Copilot en Fase 3 (Opción D).
**Motivo.** Copilot no puede producir Health reproducible, ML, series temporales ni alertas
proactivas. Análisis completo en `docs/01`.
**Consecuencia.** Asumimos la responsabilidad completa de seguridad y cumplimiento.

### ADR-002 · Permisos delegados exclusivamente en el PoC; nunca de aplicación
**Decisión.** Todo acceso a Graph se hace con el token del usuario mediante On-Behalf-Of.
Ningún permiso de aplicación (`application permission`) en el PoC.
**Motivo.** Garantiza por construcción que el sistema **nunca puede acceder a más de lo que el
usuario ya podía ver**. Es el argumento más fuerte ante Security. En modo delegado *"the
application can never exceed the user's permissions"*
([Selected permissions overview](https://learn.microsoft.com/graph/permissions-selected-overview)).
**Consecuencia.** No hay trabajos desatendidos en el PoC (ver P7 en `docs/00`).

### ADR-003 · `RetrievalProvider` como interfaz con dos implementaciones
**Decisión.** Abstraer la recuperación documental; `M365RetrievalProvider` (Retrieval API) y
`LocalVectorProvider` (pgvector), seleccionables por configuración.
**Motivo.** La disponibilidad de licencia Microsoft 365 Copilot es una incógnita bloqueante.
La abstracción la convierte en un parámetro.
**Consecuencia.** Un poco más de código; ninguna reescritura si cambia la licencia.

### ADR-004 · No usar la Excel REST API de Graph; descargar y parsear localmente
**Decisión.** `GET /drives/{driveId}/items/{itemId}/content` + `openpyxl`.
**Motivo.** Las páginas de referencia de las operaciones de rango de Graph declaran
`Files.ReadWrite` como permiso de mínimo privilegio, y sin cabecera de sesión los cambios se
persisten en el fichero. Un sistema de solo lectura no debe pedir permisos de escritura.
**Consecuencia.** No se evalúan fórmulas; se lee el valor cacheado. Las celdas de fórmula sin
valor cacheado se reportan como incidencia de calidad, no se rellenan con ceros.

### ADR-005 · Health, predicción y Early Warning se calculan en código, no con el LLM
**Decisión.** El LLM no produce ninguna cifra. Solo recupera, resume, cita y explica.
**Motivo.** Reproducibilidad, auditabilidad y defensa ante cliente.
**Consecuencia.** Más código de reglas; cero variabilidad en las cifras.

### ADR-006 · pgvector en la misma base de datos para el PoC
**Decisión.** Vectores en PostgreSQL, no en un servicio dedicado.
**Motivo.** Una sola tecnología que asegurar, respaldar y auditar; transaccionalidad entre
metadatos y vectores; sin coste ni superficie adicional.
**Alternativa considerada.** **Azure AI Search**, que ofrece control de acceso a nivel de
documento con ACLs de Entra y con ACLs de SharePoint, y filtros de seguridad
([Document-level access control](https://learn.microsoft.com/azure/search/search-document-level-access-overview)).
Es la opción correcta **cuando haya varios usuarios**, y así queda registrado.
**Consecuencia.** Migración prevista a Azure AI Search en Fase 3, o adopción de
`M365RetrievalProvider` si hay licencia Copilot.

### ADR-007 · Snapshot semanal desde el MVP
**Decisión.** Implementar `project_snapshot` en el MVP aunque no se use para entrenar todavía.
**Motivo.** Sin serie temporal no hay Early Warning ni dataset de ML, y el histórico no se
puede reconstruir a posteriori.
**Consecuencia.** Coste bajo ahora, habilita las fases 2 a 4.

### ADR-008 · Salida del LLM estructurada y validada contra el Evidence Ledger
**Decisión.** *Structured outputs* obligatorios con `claim_type` y `evidence_ids`; el backend
descarta toda afirmación no fundamentada antes de mostrarla.
**Motivo.** Es el único control efectivo contra la alucinación en un contexto empresarial.
**Consecuencia.** Respuestas a veces más cortas, y a veces un "no dispongo de información
suficiente". Es el comportamiento deseado.

### ADR-009 · El LLM no dispone de herramientas de escritura ni de acceso a red
**Decisión.** Catálogo cerrado de herramientas de solo lectura, con el usuario inyectado por
el backend.
**Motivo.** Elimina la vía principal de explotación de una inyección de prompt indirecta.
**Consecuencia.** Funciones como "envía este correo" quedan fuera del alcance del LLM; se
implementarían como acciones explícitas confirmadas por el usuario.

### ADR-010 · Abstraer el proveedor de LLM tras `LLMClient`
**Decisión.** Una interfaz; implementaciones para OpenAI Platform y Azure OpenAI.
**Motivo.** La elección depende de la residencia de datos y del contrato vigente, que aún no
están confirmados. También protege frente a la rotación de modelos.
**Consecuencia.** Los identificadores de modelo son **configuración**, nunca literales en el
código.

---

## 3. Sobre los modelos: lo que sabemos y lo que hay que verificar

**Advertencia metodológica.** Desde el entorno donde se ha preparado este análisis, el acceso
directo a `platform.openai.com` y `developers.openai.com` está bloqueado por el proxy de red.
La información siguiente proviene de búsqueda web y **debe confirmarse contra la consola de la
organización antes de fijar ningún identificador**. Por eso los modelos son configuración.

Lo que la búsqueda indica (agosto de 2026):

- Familia **GPT-5.6**, con tres variantes por capacidad/coste (`sol`, `terra`, `luna`), y
  **GPT-5.5** como modelo de trabajo complejo previo.
- **Responses API** es la API recomendada para razonamiento, uso de herramientas y flujos
  multi-turno; Chat Completions sigue soportada como estándar.
- **`text-embedding-3-large`**: hasta 3072 dimensiones, con reducción de dimensionalidad
  mediante el parámetro `dimensions`.

Criterio de asignación previsto (a confirmar con precios reales del contrato):

| Uso | Perfil de modelo | Motivo |
| --- | --- | --- |
| Síntesis de respuesta con citas | Gama media (equilibrio coste/calidad) | Volumen alto, tarea acotada |
| Explicación de predicciones | Gama media | Entrada corta, salida corta |
| Extracción estructurada de documentos en ingesta | Gama económica | Muy alto volumen |
| Análisis complejo / comparación de proyectos | Gama alta | Poco frecuente |
| Embeddings | `text-embedding-3-large` reducido a 1536 dim. | Calidad alta con la mitad de almacenamiento; compatible con HNSW de pgvector |

`[VERIFICAR]` Identificadores exactos, precios, ventana de contexto y disponibilidad en la
organización. `[VERIFICAR]` Si se usa Azure OpenAI, la disponibilidad por región del modelo
elegido.

### Nota sobre retención y residencia

- **OpenAI Platform**: por defecto se retienen datos hasta 30 días para monitorización de
  abuso. La **retención cero (ZDR)** requiere un acuerdo empresarial negociado, no está
  disponible en el plan de pago por uso estándar. Existe también residencia de datos europea
  por proyecto. → **Hay que comprobar qué tiene contratado la empresa.**
- **Azure OpenAI / Microsoft Foundry**: Microsoft documenta que prompts, completions,
  embeddings y datos de entrenamiento **no** están disponibles para OpenAI ni se usan para
  entrenar modelos base, y ofrece despliegues *DataZone* que mantienen el procesamiento
  dentro de la UE, claves gestionadas por el cliente y la posibilidad de solicitar
  **monitorización de abuso modificada** (sin almacenamiento para revisión humana)
  ([Data, privacy, and security](https://learn.microsoft.com/azure/foundry/responsible-ai/openai/data-privacy)).

Si el criterio dominante es "el dato no sale del perímetro Microsoft", **Azure OpenAI es la
opción más fácil de defender**. Si la empresa ya tiene el contrato con OpenAI firmado y
revisado por Legal, OpenAI Platform también es válido. La abstracción de ADR-010 permite
decidir esto sin frenar el desarrollo.

---

## 4. Estructura de carpetas prevista

```
ai-project-manager-assistant/
├─ docs/                       # esta documentación
├─ backend/
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ config.py             # settings con Pydantic; sin secretos en código
│  │  ├─ auth/                 # validación JWT, OBO, UserPrincipal
│  │  ├─ authz/                # resolución de proyectos autorizados
│  │  ├─ graph/                # cliente Graph: sites, drives, delta, download, retrieval
│  │  ├─ ingestion/
│  │  │  ├─ excel/             # parsers + schema mappings (YAML)
│  │  │  ├─ documents/         # extracción, chunking, embeddings
│  │  │  └─ snapshots.py
│  │  ├─ intelligence/
│  │  │  ├─ health/            # motor de reglas versionado
│  │  │  ├─ warning/           # detección de tendencia
│  │  │  ├─ prediction/        # baseline + ML + SHAP
│  │  │  ├─ whatif/            # simulador determinista
│  │  │  └─ rag/               # RetrievalProvider, prompts, validador de salida
│  │  ├─ llm/                  # LLMClient + implementaciones
│  │  ├─ models/               # SQLAlchemy
│  │  ├─ schemas/              # Pydantic (API + salida del LLM)
│  │  ├─ api/                  # routers
│  │  └─ observability/        # logging, audit, métricas
│  ├─ alembic/
│  ├─ tests/
│  └─ pyproject.toml
├─ frontend/
│  ├─ app/                     # Next.js App Router
│  ├─ components/
│  └─ lib/auth/                # MSAL React
├─ ml/
│  ├─ notebooks/               # exploración (no producción)
│  ├─ features/                # construcción de features "as-of"
│  ├─ training/
│  └─ evaluation/
├─ infra/
│  ├─ docker-compose.yml
│  └─ azure/                   # Bicep (Fase 3)
├─ .env.example                # sin valores reales
└─ README.md
```

---

## 5. Variables de entorno previstas

Ningún secreto en el código ni en el repositorio. `.env.example` se versiona **sin valores**.

```bash
# ── Entra ID ──────────────────────────────────────────────────────────
AZURE_TENANT_ID=
AZURE_API_CLIENT_ID=            # App Registration del backend
AZURE_API_CLIENT_SECRET=        # local: .env · producción: Key Vault / Managed Identity
AZURE_API_AUDIENCE=             # api://<client-id>
AZURE_SPA_CLIENT_ID=            # App Registration del frontend
GRAPH_SCOPES=                   # p.ej. "Sites.Selected Files.Read.All"

# ── Retrieval ─────────────────────────────────────────────────────────
RETRIEVAL_PROVIDER=local        # local | m365
M365_RETRIEVAL_ENABLED=false

# ── LLM ───────────────────────────────────────────────────────────────
LLM_PROVIDER=openai             # openai | azure_openai
LLM_API_KEY=
LLM_BASE_URL=
LLM_MODEL_SYNTHESIS=
LLM_MODEL_EXTRACTION=
LLM_MODEL_ANALYSIS=
EMBEDDING_MODEL=
EMBEDDING_DIMENSIONS=1536

# ── Base de datos ─────────────────────────────────────────────────────
DATABASE_URL=postgresql+asyncpg://...

# ── Aplicación ────────────────────────────────────────────────────────
APP_ENV=local
LOG_LEVEL=INFO
LOG_DOCUMENT_CONTENT=false      # NUNCA true fuera de depuración local
AUDIT_RETENTION_DAYS=365
CHUNK_RETENTION_DAYS=180
MAX_EVIDENCE_PER_ANSWER=12
```
