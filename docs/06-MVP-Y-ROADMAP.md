# 06 — MVP y roadmap

---

## 1. Alcance del MVP

El MVP es de **un usuario, un sitio de SharePoint, uno o varios proyectos**, ejecutándose en
local. Pero la arquitectura no es desechable: identidad, autorización, `tenant_id`, audit log,
Evidence Ledger y snapshots están desde el principio. Lo que se pospone es funcionalidad,
nunca los cimientos.

### Los 14 requisitos del MVP y cómo se cubren

| # | Requisito | Cómo se cubre | Fase |
| --- | --- | --- | --- |
| 1 | Login con Microsoft | MSAL.js + PKCE contra Entra ID | S1 |
| 2 | Identificar al usuario | Validación de JWT → `UserPrincipal` (oid, tid, upn) | S1 |
| 3 | Acceder a un SharePoint autorizado | Graph con OBO, `Sites.Selected` | S2 |
| 4 | Seleccionar carpeta/proyecto | Explorador de `driveItems` + alta en `project registry` | S2 |
| 5 | Leer Excel | Descarga + `openpyxl` + schema mapping + validación | S3 |
| 6 | Leer documentos | Descarga + extracción de texto | S4 |
| 7 | Indexar documentos | Chunking + embeddings + pgvector (o Retrieval API) | S4 |
| 8 | Analizar información | Motor de reglas de Health | S5 |
| 9 | Preguntar al asistente | `/ask` con herramientas + RAG + validación de salida | S5 |
| 10 | Project Health | 8 dimensiones con razones y evidencia | S5 |
| 11 | Riesgos | Desde `Risks.xlsx` + señales calculadas | S5 |
| 12 | Early Warnings | Reglas de tendencia sobre snapshots | S6 |
| 13 | Predicción de retraso | Baseline determinista calibrado (**no ML todavía**) | S6 |
| 14 | Mostrar fuentes | Evidence Ledger en toda la interfaz | transversal |

### Plan por sprints (6 semanas, dedicación parcial)

| Sprint | Objetivo | Entregable verificable |
| --- | --- | --- |
| **S1 · Cimientos** | Repositorio, Docker, esquema de BD, autenticación completa | Hago login y `/me` devuelve mi identidad desde el token |
| **S2 · Graph** | Cliente Graph con OBO, listar sitios/drives/items, alta de proyecto | Veo mis carpetas de SharePoint en la interfaz |
| **S3 · Excel** | Descarga, parseo, schema mapping, validación, cuarentena | `Project Plan.xlsx` está en base de datos, con informe de calidad |
| **S4 · Documentos + RAG** | Extracción, chunking, embeddings, `RetrievalProvider` | Pregunto sobre un `.docx` y obtengo respuesta con cita |
| **S5 · Inteligencia** | Motor de Health, herramientas del LLM, validador de salida, `/ask` | "Analiza Project X" devuelve Health con razones y fuentes |
| **S6 · EW + dashboard** | Snapshots, reglas de tendencia, baseline de riesgo, dashboard | Veo la cartera con Health, tendencia y avisos tempranos |

Cada sprint cierra con tests y documentación. No se avanza con deuda de seguridad.

### Correspondencia con los 20 pasos del encargo

| Pasos | Dónde están |
| --- | --- |
| 1–8 (análisis, arquitectura, stack, carpetas, variables, infra, App Registration, permisos) | **Este documento y `docs/00` a `docs/04`. Hecho.** |
| 9 (autenticación) | S1 |
| 10 (SharePoint/OneDrive) | S2 |
| 11 (Excel) | S3 |
| 12 (documentos) | S4 |
| 13 (RAG) | S4 |
| 14 (OpenAI) | S4–S5 |
| 15 (Project Health) | S5 |
| 16 (Early Warning) | S6 |
| 17 (baseline predictivo) | S6 |
| 18 (dashboard) | S6 |
| 19 (logging y seguridad) | Transversal a todos los sprints, no un sprint final |
| 20 (pruebas) | Transversal + evaluación del PoC (`docs/05` §6.3) |

> El paso 19 no puede ser un sprint aparte. Un sistema al que se le añade la seguridad al
> final no es un sistema seguro; el audit log y la autorización se escriben en S1.

---

## 2. Dashboard — diseño para leerlo en menos de un minuto

**Vista de cartera** (pantalla inicial): una fila por proyecto.

```
Proyecto      Cliente    Health    Riesgo   Tendencia   Avisos   Próximo hito
─────────────────────────────────────────────────────────────────────────────
Project X     Client A   ORANGE    68 % ▲   ▁▂▄▆        2        UAT · 18 sep
Project Y     Client B   GREEN     12 % ▬   ▁▁▁▁        0        Go-live · 4 oct
Project Z     Client A   YELLOW    34 % ▼   ▄▃▂▂        0        Diseño · 12 sep
```

Cuatro cosas y ninguna más: **qué proyecto**, **cómo está**, **hacia dónde va**, **qué requiere
atención**. Sin gráficos decorativos.

**Vista de proyecto**: Health por dimensión con sus razones · probabilidad de retraso con sus
factores · avisos tempranos activos · top 3 de riesgos · recomendaciones · y **siempre**, al
pie, la lista de fuentes utilizadas con su fecha de modificación.

Cada elemento numérico lleva su distintivo de tipo:
`FACT` (dato) · `PREDICTION` (modelo) · `INFERENCE` (IA) · `RECOMMENDATION` (sugerencia).

---

## 3. MVP · Future · Optional

### ✅ MVP (Fase 1 — ahora)

- Login Microsoft, identidad y autorización
- SharePoint/OneDrive por Graph con permisos delegados
- Ingesta de Excel con validación y cuarentena
- Ingesta de documentos + RAG con citas
- Project Health (8 dimensiones, motor de reglas)
- Riesgos desde el registro + señales calculadas
- Early Warning por reglas de tendencia
- Baseline de probabilidad de retraso (determinista)
- Dashboard de cartera y de proyecto
- Evidence Ledger, audit log y snapshots semanales
- 1 usuario, ejecución local

### 🔜 Future (Fases 2–3 — próximos 6–12 meses)

| Funcionalidad | Fase | Requisito previo |
| --- | --- | --- |
| Multiusuario y despliegue en Azure | 3 | Aprobación de Security, suscripción de Azure |
| Alertas a Outlook y Teams | 2 | Decisión sobre custodia de tokens (A12) |
| Outlook: correos del proyecto | 2 | Permiso `Mail.Read` con justificación propia |
| Teams: reuniones y transcripciones | 2 | Permisos de Teams; hay implicaciones de privacidad serias |
| ML supervisado real (Fases 3–4 de `docs/05`) | 3 | ≥ 50 proyectos cerrados o ≥ 500 snapshots |
| What-If completo | 2 | Modelo de planificación por capacidad |
| Comparación con proyectos históricos | 2 | ≥ 10–15 proyectos cerrados |
| Migración a Azure AI Search con ACLs | 3 | Multiusuario |
| Agente declarativo / custom engine en Copilot | 3 | Licencia Copilot + motor validado |
| Ampliación a Consultants y Support | 3 | Modelo de roles |

### 🔮 Optional (evaluar cuando haya demanda real)

Jira · Azure DevOps · ServiceNow (tickets) · Power BI (exportación de métricas) ·
MS Project · Planon · IBM TRIRIGA · 3DEXPERIENCE.

Cada una es un conector nuevo con su propio modelo de autenticación y su propio análisis de
seguridad. Ninguna se aborda antes de que el núcleo esté validado y en uso.

**Sobre Planon, TRIRIGA y 3DEXPERIENCE en concreto:** son las plataformas del negocio, y a
largo plazo son la integración más valiosa (datos reales de proyecto, no Excel intermedios).
Pero cada una exige un estudio propio de API, licenciamiento y permisos. Van al final del
roadmap por coste, no por falta de valor.

---

## 4. Criterios para pasar de fase

No se avanza por calendario, sino por evidencia:

| De → A | Condición de salida |
| --- | --- |
| MVP → Fase 2 | 4 semanas de uso real; criterios de `docs/05` §6.3 cumplidos; cero incidentes de acceso |
| Fase 2 → Fase 3 | Alertas con < 30 % de falsos positivos; Security aprueba el despliegue en Azure |
| Reglas → ML | El modelo bate al baseline en datos no vistos, con validación temporal y agrupada |
| 1 usuario → N usuarios | Revisión de seguridad completa + prueba de aislamiento entre dos usuarios con permisos distintos |
