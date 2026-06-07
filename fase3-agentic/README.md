# Fase 3 — Integración agéntica y validación del flujo CTI

## Visión general

La Fase 3 del proyecto TFM introduce una capa agéntica basada en LangGraph para mejorar el análisis de alertas de seguridad provenientes de Wazuh. El objetivo principal ha sido pasar de un triage automatizado con enriquecimiento CTI a una arquitectura más flexible, modular y trazable, manteniendo n8n como orquestador principal del flujo y usando un LLM local para el razonamiento de alto nivel.

Durante esta fase se consolidó un flujo capaz de recibir alertas, normalizarlas, enriquecerlas con inteligencia de amenazas y generar una decisión final accionable. La validación realizada confirmó que el sistema muestra correctamente los datos de Wazuh, AbuseIPDB, VirusTotal y la respuesta del agente agéntico, lo que permite cerrar la fase con una solución funcional y documentada.

## Objetivos de la fase

- Diseñar una arquitectura agéntica clara y modular.
- Desplegar un servicio independiente basado en LangGraph.
- Integrar ese servicio con n8n como orquestador.
- Validar el flujo completo con datos reales y CTI enriquecido.
- Dejar documentación técnica limpia, coherente y alineada con el estado final del proyecto.

## Resultado alcanzado

La Fase 3 culmina con un sistema que separa claramente la orquestación del razonamiento. n8n continúa gestionando la ingesta, el enriquecimiento CTI y la notificación final, mientras que LangGraph asume el análisis agéntico, la evaluación de severidad y la recomendación de respuesta. El resultado es un flujo más rápido, más estructurado y más fácil de evolucionar en fases posteriores.

Además, se validó la salida final del sistema con un mensaje coherente en Rocket.Chat que incluye la alerta Wazuh, los indicadores CTI y el análisis generado por la IA agéntica.

## Subfases

### Fase 3a — Diseño de arquitectura de agentes
En esta subfase se definió el contrato de datos entre n8n y el servicio agéntico, el estado del grafo y los agentes especializados que participan en el triage y la remediación.

[Ver README de Fase 3a](..docs/README-fase3a-arquitectura-agentes.md)

### Fase 3b — Despliegue del servicio LangGraph
En esta subfase se preparó el microservicio Python, el contenedor Docker y el endpoint HTTP que permite a n8n delegar el razonamiento agéntico en LangGraph.

[Ver README de Fase 3b](..docs/README-fase3b-despliegue-langgraph.md)

### Fase 3c — Validación final
En esta subfase se cerró el flujo final validado, corrigiendo el mapeo de Wazuh, la recuperación correcta de VirusTotal y la salida definitiva del sistema en Rocket.Chat.


## Relación con fases anteriores

Esta fase se apoya directamente en la Fase 1, donde se construyó la infraestructura base, y en la Fase 2, donde se implementó el pipeline de triage con enriquecimiento CTI. La Fase 3 amplía ese trabajo introduciendo una capa agéntica más avanzada y separando la lógica de decisión del resto de la automatización.

## Cierre

La Fase 3 deja el proyecto en un estado sólido, validado y listo para evolucionar hacia nuevas capacidades de respuesta, automatización y coordinación operativa.