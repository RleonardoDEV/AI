# 00 — Análisis de requisitos y problemas técnicos detectados

> Fase 0. Ningún apartado de este documento asume APIs, permisos o capacidades que no estén
> verificados contra documentación oficial. Lo no verificado está marcado como `[VERIFICAR]`.

---

## 1. Lectura del encargo

El sistema pedido no es un asistente documental. Son **cuatro sistemas distintos** que
comparten datos y una interfaz:

| Módulo | Naturaleza real | Tecnología correcta |
| --- | --- | --- |
| 1. Project Copilot | Recuperación + síntesis con citas | RAG + LLM |
| 2. Project Health | Cálculo determinista sobre datos tabulares | Motor de reglas + SQL. **Nada de LLM** |
| 3. Predictive Analytics | Estimación estadística | Reglas calibradas → ML supervisado |
| 4. Early Warning | Detección de tendencia sobre series temporales | Snapshots + estadística. **Nada de LLM** |

El error más caro que se puede cometer en este proyecto es usar el LLM para el módulo 2, 3
o 4. Un LLM produce un número distinto en cada ejecución, no es auditable y no se puede
defender ante un cliente. **El LLM se usa exclusivamente para: recuperar, resumir, citar y
explicar resultados que ya vienen calculados.**

De ahí la separación que atraviesa toda la arquitectura:

```
   DATOS DUROS (Excel, BD)  ──►  Motor determinista  ──►  Números  ──┐
                                                                     ├──►  LLM  ──►  Texto con citas
   DOCUMENTOS (Word/PDF)    ──►  RAG (recuperación)  ──►  Evidencia ─┘
```

---

## 2. Problemas técnicos reales detectados

Estos son los puntos donde este proyecto se rompe si no se diseñan bien desde el principio.
No son riesgos teóricos.

### P1 · El índice vectorial es una copia de datos que se desincroniza de los permisos

**El problema.** Cuando indexas documentos de SharePoint en una base vectorial propia, creas
una copia fuera del perímetro de permisos de Microsoft 365. Si mañana un administrador retira
el acceso de un usuario a `Project C`, SharePoint deja de servir el fichero al instante, pero
**tu índice sigue conteniendo el texto**. Si la comprobación de permisos de tu aplicación se
basa en metadatos capturados el día de la indexación, acabas de construir una vía de fuga.

Esto no es hipotético: es la razón por la que Azure AI Search advierte que, en su indexador
de SharePoint, *"las ACLs se capturan solo durante la indexación inicial, por lo que debe
reindexar los documentos afectados si cambian los permisos de origen, para evitar accesos
obsoletos"* ([Secure an Azure AI Search service](https://learn.microsoft.com/azure/search/search-security-best-practices#implement-document-level-access-control)).

**Cómo lo resolvemos.** Tres capas, en este orden:

1. **Autorización previa (siempre).** El usuario solo puede consultar proyectos que están en
   su `project registry` autorizado. Ese registro se recalcula contra Graph, no se cachea
   indefinidamente.
2. **Verificación en el momento de responder (siempre).** Antes de devolver una cita, el
   backend comprueba con el token del usuario que el `driveItem` sigue siendo accesible
   (`GET /drives/{driveId}/items/{itemId}` con el token OBO del usuario). Si devuelve 403/404,
   la cita se descarta y el chunk se marca para reindexación. Coste: una llamada Graph por
   documento citado (típicamente 3–6 por respuesta), aceptable.
3. **Reconciliación periódica.** El *delta query* de Graph
   (`GET /drives/{id}/root/delta`, [doc](https://learn.microsoft.com/graph/api/driveitem-delta?view=graph-rest-1.0))
   detecta altas, bajas y modificaciones. Los elementos con la faceta `deleted` se purgan del
   índice.

> **Decisión:** la comprobación de permisos en el momento de responder es obligatoria y no es
> opcional por rendimiento. Es el control que hace que el sistema sea defendible ante Security.

### P2 · La Retrieval API de Microsoft 365 Copilot resuelve P1… pero no sirve para los Excel

Microsoft tiene exactamente la respuesta a P1: la **Microsoft 365 Copilot Retrieval API**
(`POST https://graph.microsoft.com/v1.0/copilot/retrieval`). Devuelve extractos de texto
relevantes de SharePoint/OneDrive **ya recortados por los permisos del usuario que llama**,
sin copiar ni reindexar nada
([referencia](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/ai-services/retrieval/copilotroot-retrieval),
[overview](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/ai-services/retrieval/overview)).

Es la opción más segura para documentos. Pero tiene límites documentados que la descartan
como solución **única**:

| Límite documentado | Impacto en este proyecto |
| --- | --- |
| Solo permisos **delegados**; application no soportado | Bien: encaja con nuestro modelo. Pero exige `Files.Read.All` + `Sites.Read.All` |
| Requiere licencia Microsoft 365 Copilot (o Pay-as-you-go) | **Bloqueante si solo hay Copilot Chat.** Ver `docs/08` |
| Recuperación semántica solo para `.doc/.docx/.pptx/.pdf/.aspx/.one`; el resto solo léxica | Los `.xlsx` quedan fuera de la recuperación semántica |
| Recuperación de texto en tablas limitada a `.doc/.docx/.pptx` | **Los datos de `Project Plan.xlsx` no son recuperables por esta vía** |
| Máx. 25 resultados, 200 peticiones por usuario y hora | Suficiente para chat; insuficiente para ingesta masiva |
| PAYG: fuentes a nivel de tenant (SharePoint) sí, OneDrive **no** | Si el PoC usa OneDrive personal, PAYG no cubre |

**Conclusión arquitectónica.** Arquitectura **híbrida y con el retrieval abstraído**:

- **Excel → pipeline propio.** Siempre. Descarga, parseo, validación, base de datos relacional.
  Es la fuente de los números; necesita ser exacta, no "recuperable".
- **Documentos (Word/PDF/notas) → interfaz `RetrievalProvider`** con dos implementaciones
  intercambiables por configuración:
  - `M365RetrievalProvider` (preferida si hay licencia Copilot): cero copia de datos.
  - `LocalVectorProvider` (pgvector): funciona sin licencia Copilot, con las mitigaciones de P1.

Esto evita la peor decisión posible: atarnos a una sola vía antes de saber qué licencias hay.

### P3 · La Excel REST API de Graph pide permisos de escritura para operaciones de lectura

Hay una **contradicción en la documentación oficial de Microsoft** que afecta directamente al
principio de mínimo privilegio:

- La página general [Working with Excel in Microsoft Graph](https://learn.microsoft.com/graph/api/resources/excel?view=graph-rest-1.0)
  dice: *"Files.Read (for read actions)"*.
- Las páginas de referencia de las operaciones que realmente necesitamos
  ([Worksheet: UsedRange](https://learn.microsoft.com/graph/api/worksheet-usedrange?view=graph-rest-1.0),
  [Worksheet: Range](https://learn.microsoft.com/graph/api/worksheet-range?view=graph-rest-1.0),
  [TableColumn: Range](https://learn.microsoft.com/graph/api/tablecolumn-range?view=graph-rest-1.0))
  declaran como permiso de **mínimo privilegio: `Files.ReadWrite`**.
- Además, la misma página avisa: *"If you don't use a session header, changes made during the
  API call **are** persisted to the file."*

Pedir `Files.ReadWrite.All` para un sistema que solo lee es exactamente lo que Security va a
rechazar, y con razón.

**Decisión (ADR-004).** **No usamos la Excel REST API.** Descargamos el fichero
(`GET /drives/{driveId}/items/{itemId}/content`, que funciona con `Files.Read.All` /
`Sites.Read.All` / `Sites.Selected`) y lo parseamos localmente con `openpyxl` en modo
solo lectura.

Ventajas: permiso estrictamente de lectura, sin sesiones de workbook, sin el límite de
throttling específico de Excel (1.500 req/10 s por app y tenant,
[límites](https://learn.microsoft.com/graph/throttling-limits#excel-service-limits)),
y control total del parseo.

**Limitación honesta de esta decisión:** `openpyxl` no evalúa fórmulas. Con `data_only=True`
lee el último valor **cacheado por Excel**. Si un fichero se editó por un proceso que no
recalculó, esas celdas llegan como `None`. Mitigación: el validador detecta celdas de fórmula
sin valor cacheado y las reporta como incidencia de calidad de datos en vez de inventar un 0.

### P4 · Los Excel de Project Management del mundo real no son tabulares

Un `Project Plan.xlsx` real suele tener: un logo en las primeras filas, la cabecera en la
fila 7, celdas combinadas, fechas guardadas como texto (`15/08/2026`, `15-Aug`, `2026-08-15`
en la misma columna), filas de subtotal intercaladas, columnas renombradas entre versiones y
tres pestañas con nombres distintos según quién lo creó.

Un parser "genérico e inteligente" fallará en silencio, que es el peor modo de fallo posible
para un sistema del que se esperan cifras de riesgo.

**Cómo lo resolvemos.**

1. **Contrato de datos explícito** (`schema mapping`) por tipo de plantilla, en YAML versionado:
   qué pestaña, en qué fila está la cabecera, qué columna del fichero corresponde a qué campo
   canónico, y qué valores del cliente equivalen a cada `status` canónico.
2. **Validación con Pydantic** fila a fila. Las filas que no validan **no se descartan en
   silencio**: van a una tabla de cuarentena con el motivo.
3. **Informe de calidad de datos** por ingesta: filas leídas, válidas, en cuarentena, campos
   nulos críticos. Si el porcentaje de cuarentena supera un umbral, el Health del proyecto se
   marca como `UNKNOWN`, no como verde.
4. **Nunca inferir.** Si no se puede mapear una columna, el sistema lo dice. No adivina.

> Es preferible un sistema que responde "no tengo datos fiables de presupuesto en este
> proyecto" a uno que responde "presupuesto en verde" porque leyó una celda vacía como 0.

### P5 · No hay datos históricos, y sin diseño previo nunca los habrá

Con menos de ~50 proyectos cerrados y limpios, entrenar XGBoost produce un modelo que
memoriza el nombre del Project Manager. No es un problema de algoritmo, es de tamaño muestral.

El problema serio no es ese: es que **si el sistema no empieza a registrar el estado semanal
de los proyectos desde el primer día, dentro de 12 meses seguiremos sin dataset**.

**Decisión de diseño temprana y crítica:** la tabla `project_snapshot` (una foto semanal
inmutable de ~30 métricas por proyecto) se implementa en el **MVP**, aunque en el MVP no se
use para entrenar nada. Es el activo que hace posible la Fase 3 y 4. Cuesta poco ahora y no
se puede reconstruir después.

Los snapshots resuelven además el módulo 4: **sin serie temporal no hay Early Warning**,
porque "el riesgo subió del 42 % al 68 % en 7 días" requiere saber cuánto era hace 7 días.

### P6 · Fuga temporal (*leakage*) en el modelo de predicción de retraso

El listado de features propuesto en el encargo incluye `actual duration`, `actual hours` y
`delayed tasks`. Si se entrena con esas variables tal cual, el modelo aprende a predecir el
retraso a partir del retraso ya ocurrido: AUC de 0,95 en validación y un modelo inútil en
producción.

**Cómo lo resolvemos.**

- Features **"as-of"**: todas se calculan con la información disponible en la semana *t*,
  nunca con datos posteriores.
- Horizonte explícito: se predice *"¿se retrasará el próximo hito más de N días?"*, evaluado
  en la semana *t + h*.
- Validación **temporal y agrupada**: `GroupKFold` por `project_id` + corte temporal.
  Los snapshots de un mismo proyecto están fuertemente correlacionados; si caen a ambos lados
  del split, la métrica miente.

### P7 · El trabajo en segundo plano no tiene usuario, y todo nuestro modelo depende del usuario

El modelo de seguridad se basa en permisos **delegados**: la app nunca puede acceder a más de
lo que el usuario ve. Pero la ingesta nocturna y las alertas programadas no tienen un usuario
delante. Y el flujo On-Behalf-Of *solo funciona con principales de usuario*, no con tokens de
aplicación ([OBO — Client limitations](https://learn.microsoft.com/entra/identity-platform/v2-oauth2-on-behalf-of-flow#client-limitations)).

**Cómo lo resolvemos, por fases:**

- **PoC (1 usuario):** la ingesta la dispara el usuario desde la interfaz, con su propio
  token. Sin trabajos desatendidos. Simple, seguro y suficiente.
- **Fase 2 (alertas programadas):** *refresh token* del usuario en caché cifrada
  (Key Vault / cifrado a nivel de columna con clave gestionada), con consentimiento explícito
  del usuario, caducidad y revocación. Se documenta como decisión que **Security debe aprobar**.
- **Fase 3 (multi-usuario, ingesta central):** identidad de aplicación con
  **`Sites.Selected`** y concesión explícita sitio a sitio, más recorte de permisos por usuario
  en el momento de la consulta. Nunca `Files.Read.All` de aplicación.

### P8 · "What if" no se puede responder con el modelo predictivo

Un modelo entrenado con 40 proyectos no puede estimar el efecto causal de retirar un
desarrollador dos semanas. Presentarlo como predicción sería engañoso.

**Cómo lo resolvemos.** El What-If **no invoca el modelo ML como oráculo causal**: es un
**simulador determinista** sobre el plan (recalcula capacidad, carga, holgura y fechas de
hitos con las restricciones modificadas) y vuelve a ejecutar el motor de reglas. El resultado
se presenta siempre como *escenario* con sus supuestos visibles y en rango, nunca como una
cifra puntual. Detalle en `docs/05-ML-Y-ANALYTICS.md`.

### P9 · Etiquetas de confidencialidad y sobrecompartición

Si un documento tiene una etiqueta de sensibilidad de Purview que restringe su uso, copiarlo
a un índice propio puede saltarse esa protección. La Retrieval API respeta las etiquetas por
diseño ([Security and authentication for Microsoft 365 Copilot APIs](https://learn.microsoft.com/microsoft-365/copilot/extensibility/copilot-apis-security-authentication));
un índice propio **no lo hace solo**.

Mitigación en `LocalVectorProvider`: leer la etiqueta del `driveItem` durante la ingesta y
excluir del índice todo lo que supere el nivel de clasificación autorizado para el sistema.
Requiere que IT defina cuál es ese nivel. `[VERIFICAR con IT]`

Nota relacionada: *Restricted SharePoint Search* **está siendo retirada** — desde el 31 de
julio de 2026 no se admiten nuevas activaciones, y Microsoft dirige a *Restricted Content
Discovery* ([doc](https://learn.microsoft.com/sharepoint/restricted-sharepoint-search)).
No conviene apoyar ningún control de este proyecto sobre esa función.

### P10 · Throttling y coste

- Graph: límite global de 130.000 peticiones por app / 10 s y límites por servicio; hay que
  respetar `Retry-After` — ignorarlo provoca más throttling y puede acabar en bloqueo de la
  aplicación ([throttling](https://learn.microsoft.com/graph/throttling),
  [SharePoint](https://learn.microsoft.com/sharepoint/dev/general-development/how-to-avoid-getting-throttled-or-blocked-in-sharepoint-online)).
- Retrieval API: 200 peticiones por usuario y hora.
- Embeddings: reindexar todo en cada ejecución es caro e innecesario.

Mitigación transversal: `delta query` para no releer lo que no cambió, **hash de contenido**
(SHA-256) por documento y por chunk para no volver a embeber lo idéntico, `Retry-After`
respetado con backoff exponencial, y JSON batching donde aplique.

### P11 · Acceso Condicional puede romper el flujo On-Behalf-Of

Si el tenant exige dispositivo conforme o MFA con `claims challenge` para acceder a
SharePoint, la petición OBO del backend puede fallar con un desafío de claims que hay que
propagar al cliente. MSAL Python lo contempla vía el parámetro `claims_challenge` de
`acquire_token_on_behalf_of`
([doc](https://learn.microsoft.com/python/api/msal/msal.application.confidentialclientapplication?view=msal-py-latest)),
pero hay que implementarlo explícitamente. **Es un punto a validar con IT antes de escribir
código**, porque cambia el diseño del frontend.

### P12 · Ambigüedad de "proyecto"

Una carpeta de SharePoint no es un proyecto. Hace falta un registro explícito
(`project`) que relacione: nombre canónico, cliente, tecnología (Planon / Dassault /
3DEXPERIENCE / TRIRIGA), PM responsable, sitio y carpeta de SharePoint, fechas de referencia
y plantillas de Excel esperadas. Inferirlo del nombre de la carpeta es frágil y produce
mezclas de datos entre clientes. El registro se crea al dar de alta el proyecto en la interfaz.

---

## 3. Riesgos de seguridad identificados

Clasificados por lo que Security preguntará. El detalle de controles está en
`docs/04-SEGURIDAD-Y-PERMISOS.md`.

| # | Riesgo | Severidad | Control principal |
| --- | --- | --- | --- |
| S1 | Permisos excesivos (`Files.Read.All` tenant-wide) | Alta | Preferir `Sites.Selected` delegado; nunca permisos de aplicación en el PoC |
| S2 | Índice vectorial desincronizado de las ACL | **Crítica** | Verificación de acceso en tiempo de respuesta + delta sync + purga |
| S3 | Inyección de prompt indirecta desde documentos | **Crítica** | Separación datos/instrucciones, sin herramientas de escritura, sanitización de salida |
| S4 | Exfiltración vía la respuesta del LLM (imágenes/enlaces markdown) | Alta | Prohibir imágenes remotas y enlaces no allow-listed en el renderizado |
| S5 | Fuga de datos en logs y trazas | Alta | Prohibido registrar contenido; solo IDs, hashes y métricas |
| S6 | Custodia de *refresh tokens* (Fase 2) | Alta | Cifrado con clave gestionada, caducidad, revocación, aprobación de Security |
| S7 | Etiquetas de sensibilidad ignoradas por el índice propio | Alta | Filtrado por etiqueta en ingesta |
| S8 | Envío innecesario de datos confidenciales al modelo | Media | Minimización: solo extractos recuperados, nunca documentos completos |
| S9 | Retención y residencia de datos en el proveedor de LLM | Media | ZDR / Azure OpenAI con despliegue EU; validar contrato |
| S10 | Datos personales de empleados (PM, equipo) en el índice | Media | Base legal y DPIA; minimizar; no indexar evaluaciones de desempeño |
| S11 | Escalada por confusión de identidad (el LLM elige el proyecto) | **Crítica** | El `project_id` se valida contra la lista autorizada en **cada** llamada a herramienta |
| S12 | Documento envenenado que altera cifras (no solo instrucciones) | Media | Los números vienen de la BD validada, no del texto libre |

---

## 4. Qué queda explícitamente fuera de la Fase 0

- Outlook, Teams, correo y reuniones (Fase 2+).
- Jira, Azure DevOps, ServiceNow, Power BI, MS Project (Fase 3+ / opcional).
- Planon, TRIRIGA, 3DEXPERIENCE como fuentes de datos (opcional, requiere análisis propio).
- Multi-tenant real (el modelo de datos lo prevé; la funcionalidad no se implementa).
- Fine-tuning de modelos (no está justificado y complica la gobernanza).
