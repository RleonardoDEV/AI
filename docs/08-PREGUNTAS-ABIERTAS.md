# 08 — Preguntas abiertas y datos necesarios para empezar

Solo está aquí lo que **realmente cambia el trabajo**. Todo lo demás lo resuelvo con
decisiones razonables por defecto y lo documento.

---

## A · Bloqueantes (necesarias antes de escribir código)

### A1 · ¿Qué Copilot tenéis exactamente?

- [ ] **Microsoft 365 Copilot** con licencia de pago (grounding en datos de trabajo)
- [ ] **Copilot Chat** incluido con M365 (solo grounding web)
- [ ] No lo sé / lo tengo que consultar con IT

**Por qué importa.** Con licencia de pago podemos usar la **Retrieval API**, que elimina por
completo el riesgo crítico de este proyecto (índice de documentos desincronizado de los
permisos, S2 en `docs/00`). Sin ella, construimos el índice nosotros con las mitigaciones ya
diseñadas. El código está preparado para las dos vías (ADR-003), pero saberlo cambia el orden
de trabajo del sprint 4.

### A2 · ¿Dónde ejecuto el PoC?

- [ ] **Mi portátil corporativo** (recomendado: coste cero, aprobación más sencilla)
- [ ] Hay suscripción de Azure disponible desde ya
- [ ] Otro (servidor interno, etc.)

**Por qué importa.** Determina el despliegue del sprint 1 y qué hay que pedir a IT.

### A3 · ¿Qué proveedor de LLM usamos?

- [ ] **OpenAI Platform** empresarial (ya contratada)
- [ ] **Azure OpenAI / Microsoft Foundry** (el dato no sale del perímetro Microsoft)
- [ ] Ambos disponibles, decide tú

**Por qué importa.** Azure OpenAI es más fácil de defender ante Security (mismas garantías
contractuales que el resto de Azure, despliegues *DataZone* en la UE, monitorización de abuso
modificable). OpenAI Platform requiere confirmar la retención contratada: por defecto son
30 días, y la retención cero exige acuerdo empresarial negociado.

**Sub-pregunta:** ¿la empresa es europea o tiene requisito de residencia de datos en la UE?

### A4 · ¿Qué permisos puede conceder IT?

- [ ] **`Sites.Selected` delegado** + concesión `read` sobre el sitio del PoC (mínimo privilegio real)
- [ ] **`Files.Read.All` + `Sites.Read.All` delegados** (necesarios para la Retrieval API)
- [ ] Todavía no lo sé

**Por qué importa.** Son excluyentes: `Files.Read.All` anula el efecto restrictivo de
`Sites.Selected`. Determina el App Registration y el proveedor de recuperación.

---

## B · Necesarias antes del sprint 3 (ingesta de Excel)

### B1 · Estructura real de vuestros Excel

Es lo que más va a determinar si la ingesta funciona a la primera. Para cada plantilla
(`Project Plan`, `Risks`, `Resources`, `Budget`) necesito:

- Nombre exacto del fichero y de las pestañas relevantes
- **En qué fila está la cabecera** (rara vez es la 1)
- Nombres exactos de las columnas, tal cual aparecen
- Valores posibles de `Status` (¿`Blocked`? ¿`Bloqueado`? ¿`On Hold`? ¿`En curso`?)
- Formato de las fechas (`dd/mm/aaaa`, texto, número de serie de Excel…)
- Si hay celdas combinadas, filas de subtotal o filas de agrupación

**La forma más eficiente:** enviar un fichero real **anonimizado** (nombres de cliente y
personas sustituidos, cifras alteradas), conservando la estructura. Con eso escribo el
`schema mapping` correcto en lugar de adivinar. Si no es posible, una captura de las 10
primeras filas de cada pestaña ya ayuda mucho.

### B2 · Sitio y carpeta del PoC

- URL exacta del sitio de SharePoint
- Ruta de la carpeta del proyecto de prueba
- ¿Es un sitio de equipo o una biblioteca en tu OneDrive? *(afecta a los permisos y a si la
  modalidad PAYG de la Retrieval API es aplicable — OneDrive queda fuera)*

### B3 · Uno o varios proyectos

¿Empezamos con **un** proyecto o con dos o tres? Con tres se ve el valor del dashboard de
cartera; con uno se avanza más rápido. **Recomendación: uno para construir, tres para probar.**

---

## C · Necesarias antes del sprint 6 (predicción y Early Warning)

### C1 · ¿Cuántos proyectos históricos cerrados hay, y en qué estado?

- Número aproximado de proyectos **cerrados** con fechas reales de inicio y fin
- ¿Están en el mismo formato de Excel que los actuales?
- ¿Hay registro de la **fecha planificada original** (línea base) o solo la final?

**Por qué importa.** Es lo que decide si estamos en la Fase 1, 2 o 3 de `docs/05` §3.2.
Sin línea base original no se puede calcular el retraso, que es la etiqueta del modelo.

**Si la respuesta es "pocos o ninguno limpio", no es un problema**: el diseño lo contempla.
Empezamos con reglas y los snapshots semanales construyen el dataset a partir de hoy.

### C2 · ¿Qué es "retraso" para vuestro negocio?

¿Un proyecto se considera retrasado si se pasa de la fecha de fin? ¿Si se pasa un hito
contractual? ¿Cuántos días de tolerancia hay? Esto define la etiqueta del modelo, y si se
define mal, todo lo demás sobra.

### C3 · Umbrales de Health

¿Tienes criterios propios ya en uso? Por ejemplo: *"a partir del 15 % de desviación es
ámbar; a partir del 25 %, rojo"*. Si los hay, los uso. Si no, propongo unos por defecto,
documentados y ajustables, y los calibramos con tu juicio durante las primeras semanas.

---

## D · Decisiones que tomo yo salvo que digas lo contrario

Para no bloquear el arranque, asumo estas por defecto:

| Decisión | Por defecto | Cámbialo si… |
| --- | --- | --- |
| Idioma de la interfaz | Español, con términos técnicos en inglés (`Health`, `Early Warning`) | Prefieres todo en inglés |
| Idioma de la documentación técnica | Español | El equipo o IT trabajan en inglés |
| Idioma de las respuestas del asistente | El mismo de la pregunta | — |
| Nombre del repositorio y del paquete | `ai-project-manager-assistant` | — |
| Tamaño de chunk | 800–1000 tokens, 15 % de solape | — |
| Embeddings | `text-embedding-3-large` reducido a 1536 dimensiones | Prefieres 3072 (mejor calidad, más almacenamiento) |
| Periodicidad del snapshot | Semanal, lunes | — |
| Retención de chunks | 180 días | La política corporativa diga otra cosa |
| Zona horaria y calendario laboral | Europa/Madrid, lunes a viernes | El equipo esté en otra zona o haya festivos que respetar |

---

## E · Qué hago mientras tanto

Puedo empezar **hoy** sin ninguna de las respuestas anteriores, porque lo siguiente no depende
de ellas:

1. Estructura del repositorio, `docker compose`, configuración tipada y `.env.example`
2. Esquema completo de base de datos y migraciones de Alembic
3. Motor de reglas de Health con umbrales en YAML + tests con datos sintéticos
4. Parser de Excel con `schema mapping` genérico + suite de tests con ficheros de ejemplo
   deliberadamente sucios (cabeceras desplazadas, fechas como texto, celdas combinadas)
5. Evidence Ledger, validador de salida y audit log
6. Simulador What-If determinista
7. Esqueleto del frontend y del dashboard con datos de ejemplo

Es aproximadamente el 60 % del sprint 1 al 3, y ninguna línea se pierde según cuáles sean las
respuestas.

**Lo único que sí necesito antes de empezar la parte de Microsoft (sprint 2) es A4**, porque
determina cómo se construye el App Registration.
