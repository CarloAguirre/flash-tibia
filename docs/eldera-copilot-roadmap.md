# Eldera Copilot AI Roadmap

Estado: pausado por decision de producto el 2026-05-14. Fases 0, 1 y 2 quedaron implementadas para el stack Canary 15; Fase 3 quedo iniciada con recomendador deterministico read-only y cards; Fase 4 quedo iniciada con ruta visual preview-only hacia The Oracle. El modulo `game_ai_copilot` no se carga en el cliente browser actual, por lo que el boton Eldera Copilot no aparece. Gemini, tasker, autowalk y acciones siguen desactivados.

Este documento resume la ruta propuesta para empezar a iterar sobre **Eldera Copilot**, una integracion oficial de IA dentro del gameplay de Eldera. La idea no es crear un chat generico ni un bot externo, sino un asistente contextual integrado al cliente y validado por el servidor.

## Objetivo

Construir Eldera Copilot como un asistente in-game que pueda:

- responder dudas del jugador con contexto real del personaje;
- recomendar zonas, tareas, supplies y proximos pasos;
- planificar rutas y mostrarlas visualmente;
- ejecutar tareas guiadas solo cuando el servidor las valide;
- evolucionar hacia un tasker oficial, auditable y controlado por reglas del servidor.

El modelo de IA recomendado para empezar es Gemini Free, Gemini Flash o un modelo gratuito/de muy bajo costo. La IA debe usarse para interpretar intenciones y redactar respuestas, no como fuente unica de verdad ni como autoridad de acciones.

## Estado Actual

Fase 0 ya esta operativa en el stack Canary 15:

- opcode reservado: `ExtendedIds.ElderaCopilot = 216`;
- modulo cliente minimo: `otclient/modules/game_ai_copilot/`;
- panel in-game con historial, input y boton Send;
- request dummy por ExtendedOpcode JSON desde OTClient;
- handler activo en Canary: `canary-main/data/scripts/creaturescripts/others/extended_opcode.lua`;
- respuesta echo con contexto minimo del jugador;
- validado en navegador con `dummy ping`, respuesta `Canary`, `Echo` y `Context` visibles.

Fase 1 ya cambio el request a tipo `chat`, input vacio con placeholder y respuesta read-only desde Canary/gateway. La iteracion actual separa `codec`, `context`, `validator`, `mock` y `gateway` en `canary-main/data/libs/ai_copilot/`, agrega rate limit basico, devuelve errores estructurados por ExtendedOpcode, agrega `ai-gateway/` en modo mock y conecta Canary con el gateway por HTTP async en C++ con fallback local. Fase 2 agrega KB curada en `ai-gateway/kb/` y retrieval deterministico. Fase 3 agrega reglas de recomendacion y cards renderizadas en `game_ai_copilot`. Fase 4 agrega el primer contrato `route` preview-only y overlay temporal en minimap. Gemini todavia no debe integrarse hasta que el mock, el contrato, la KB y la experiencia read-only esten estables.

## Diagnostico Del Repositorio

El stack moderno principal esta en `docker-compose.canary.yml`:

- `canary-main`: servidor Canary 15, fuente autoritativa del estado del juego.
- `otclient`: cliente C++/Lua con build browser via Emscripten.
- `web15/public`: artefactos web del cliente browser.
- `myaac-15.xx`: account manager y shell web con iframe del juego.
- `proxy/server.js`: puente WebSocket a TCP para login/game protocol.
- `web/server.js`: servidor estatico con headers COOP/COEP y proxy de login HTTP.
- `ai-gateway/`: servicio interno mock-only para el contrato Copilot backend.

El stack legacy `docker-compose.yml` + `tfs` corresponde al servidor 8.60. No deberia ser el objetivo inicial de IA salvo que se decida soportar tambien esa version.

## Principios Tecnicos

1. **Servidor autoritativo**: el cliente puede mostrar UI y ejecutar acciones locales, pero Canary valida estado, permisos y riesgos.
2. **Gemini fuera del navegador**: la clave nunca debe llegar al browser ni a `web15/public`.
3. **IA con contexto curado**: no pedirle al modelo que deduzca todo desde el repo o desde texto libre. Usar KB y reglas versionadas.
4. **Acciones deterministicas**: rutas, compras, tareas y movimientos deben salir de reglas/waypoints/validadores, no de texto generado por el modelo.
5. **Iterar read-only primero**: chat contextual y recomendaciones antes de cualquier automatizacion.
6. **Auditoria desde el inicio**: registrar requests, respuestas, acciones propuestas, confirmaciones y errores.

## Bloques Existentes Reutilizables

### Comunicacion Cliente-Servidor

- `otclient/modules/gamelib/protocolgame.lua` tiene helpers para ExtendedOpcode JSON.
- `otclient/modules/game_tasks/tasks.lua` ya muestra un patron real con ExtendedOpcode JSON usando opcode `215`.
- `canary-main/data/libs/functions/player.lua` contiene `Player.sendExtendedOpcode`.
- `canary-main/data/scripts/creaturescripts/others/#extended_opcode.lua` muestra el hook Lua de ExtendedOpcode.
- `canary-main/src/server/network/protocol/protocolgame.cpp` habilita y parsea ExtendedOpcode.
- `canary-main/src/game/game.cpp` despacha el opcode hacia creature events.

Decision: reservar un opcode nuevo para IA. No reutilizar `215`, porque ya esta usado por `game_tasks`.

### UI Del Cliente

- `otclient/modules/game_interface/gameinterface.lua` expone paneles principales como `getLeftPanel`, `getLeftExtraPanel`, `getRightPanel` y `getMapPanel`.
- La UI de miniwindows existente permite agregar un panel estilo juego para Eldera Copilot.
- `otclient/modules/game_minimap/minimap.lua` y `otclient/src/client/uiminimap.cpp` permiten trabajar con minimap y marcadores.

### Estado Del Jugador

- En cliente: `LocalPlayer`, inventario, containers, battle list, quest log, minimap y autowalk.
- En servidor: `Player` Lua bindings para nivel, mana, skills, vocation, town, storages, dinero, slots, items, containers y map marks.
- `canary-main/config.lua` contiene reglas/rates importantes para respuestas de contexto.

### Movimiento Y Rutas

- `otclient/src/client/localplayer.cpp` ya tiene `LocalPlayer::autoWalk` con pathfinding local.
- `otclient/meta.lua` documenta APIs como `g_map.findPath`, `g_game.autoWalk`, `g_game.stop` y getters del jugador.
- `Tile:setFill` existe, pero no es ideal para rutas porque puede tapar el dibujo normal del tile. Para la primera etapa conviene usar minimap markers.

## Arquitectura Objetivo

```text
OTClient browser / desktop
  game_ai_copilot module
  - panel de chat/contexto
  - route overlay en minimap
  - acciones confirmables
        |
        | ExtendedOpcode JSON
        v
Canary server
  ai_copilot Lua bridge
  - context builder
  - policy validator
  - rate limit por jugador/cuenta
  - audit log
        |
        | HTTP interno o cola DB
        v
AI Gateway
  - Gemini Free/Flash o mock local
  - prompt templates
  - knowledge base curada
  - normalizacion de respuestas estructuradas
        |
        v
Canary valida respuesta y envia resultado al jugador
```

### Servicios Nuevos Propuestos

- `ai-gateway/`: servicio backend aislado con la clave de Gemini, prompts, schemas, KB y fallback mock.
- `otclient/modules/game_ai_copilot/`: modulo Lua/OTUI del cliente para panel, historial, route overlay y comandos.
- `canary-main/data/libs/ai_copilot/`: librerias Lua del servidor para contexto, validacion, rate limits y serializacion.
- `canary-main/data/scripts/creaturescripts/ai_copilot/`: evento ExtendedOpcode dedicado.
- `canary-main/data/ai/` o `ai-gateway/kb/`: KB curada de zonas, NPCs, rutas, reglas y recomendaciones.

### Transporte Gateway

Hay dos opciones razonables:

1. **Cola DB para la primera version**: Canary inserta request en MariaDB, `ai-gateway` procesa y escribe respuesta. Es simple y evita agregar bindings HTTP al Lua del servidor al inicio.
2. **HTTP interno servidor -> gateway**: mas limpio a largo plazo, pero puede requerir cambios C++ o exponer una funcion Lua nueva basada en libcurl. Canary ya tiene infraestructura de webhook con curl, pero esta orientada a Discord y no deberia reutilizarse directamente sin adaptar el contrato.

Recomendacion actualizada: investigar primero si un HTTP interno servidor -> gateway es viable sin bloquear el servidor. Usar cola DB solo si HTTP requiere demasiado cambio C++ para la primera iteracion.

## Contrato Inicial De Mensajes

Opcode: `AI_COPILOT_OPCODE = 216`. No usar `215`, porque ya esta usado por `game_tasks`.

Request cliente -> servidor:

```json
{
  "v": 1,
  "requestId": "uuid-or-short-id",
  "type": "chat",
  "text": "donde puedo levelear?",
  "clientState": {
    "visibleFloor": 7,
    "selectedThing": null,
    "uiContext": "copilot-panel"
  }
}
```

Contexto agregado por servidor:

```json
{
  "player": {
    "name": "...",
    "level": 42,
    "vocation": "...",
    "position": { "x": 0, "y": 0, "z": 7 },
    "healthPercent": 100,
    "manaPercent": 80,
    "money": 0
  },
  "server": {
    "worldType": "pvp",
    "protectionLevel": 7,
    "rates": { "exp": 1, "skill": 1, "loot": 1, "magic": 1 }
  },
  "permissions": {
    "canSuggestRoute": true,
    "canSuggestTask": false,
    "canExecuteAction": false
  }
}
```

Response servidor -> cliente:

```json
{
  "v": 1,
  "requestId": "uuid-or-short-id",
  "type": "answer",
  "message": "Te conviene empezar por una zona segura cercana...",
  "cards": [],
  "route": null,
  "actions": [],
  "requiresConfirmation": false
}
```

Reglas del contrato:

- limitar tamano de `text` y payload total;
- rechazar JSON invalido;
- rate limit por jugador/cuenta;
- nunca aceptar acciones libres generadas por el modelo;
- toda accion debe venir de una whitelist del servidor;
- incluir `requestId` para correlacion, timeout y auditoria.

## Plan Por Fases

### Fase 0 - Base De Iteracion (Completada)

Superficie: ambos, con panel minimo visible para validar el circuito.

Objetivo: dejar definido y probado el contrato tecnico minimo antes de tocar IA real o gameplay.

Estado: completada para el stack Canary 15. La implementacion actual envia `dummy ping`, Canary responde echo/contexto minimo y el panel muestra la respuesta dentro del juego. No integra Gemini, rutas ni tasker.

Revisar:

- `docker-compose.canary.yml`
- `docs/canary15.md`
- `otclient/init.lua`
- `otclient/modules/gamelib/protocolgame.lua`
- `canary-main/data/libs/functions/player.lua`
- `canary-main/data/scripts/creaturescripts/others/#extended_opcode.lua`

Crear:

- definicion de opcode IA;
- modulo minimo `game_ai_copilot`;
- request dummy por ExtendedOpcode;
- respuesta echo desde Canary con contexto minimo del jugador;
- schema JSON inicial documentado en el contrato.

Flujo de datos:

```text
Cliente envia request dummy -> servidor agrega contexto minimo -> servidor responde echo/error -> cliente muestra respuesta
```

Riesgos:

- colision de opcode;
- payloads muy grandes;
- mezclar stack Canary 15 con stack legacy 8.60;
- modificar `web15/public` como si fuera fuente.

Pruebas minimas:

- login al cliente Canary 15;
- envio y recepcion de opcode dummy;
- JSON invalido devuelve error controlado;
- desconexion limpia sin errores en logs.

### Fase 1 - Chat Contextual Read-Only (En Progreso)

Superficie: cliente + servidor + backend.

Objetivo: primer Eldera Copilot usable como panel de chat in-game, sin acciones automaticas.

Estado: iniciada. El cliente ya envia mensajes como `type = "chat"` y el panel esta preparado para texto libre. Canary responde todavia con mock local y contexto minimo; el gateway externo queda para el siguiente paso de esta fase.

Implementado en esta fase:

- `canary-main/data/libs/ai_copilot/codec.lua`: serializacion JSON minima y lectura del request.
- `canary-main/data/libs/ai_copilot/context.lua`: contexto read-only de jugador y servidor.
- `canary-main/data/libs/ai_copilot/validator.lua`: tipo de request, tamano maximo y rate limit basico.
- `canary-main/data/libs/ai_copilot/mock.lua`: respuesta local deterministica, sin Gemini.
- `canary-main/data/libs/ai_copilot/gateway.lua`: arma el request contextual hacia el gateway y conserva fallback local.
- `canary-main/src/server/network/ai_gateway/`: cliente HTTP async basado en curl/thread pool que vuelve al dispatcher para responder por ExtendedOpcode.
- `ai-gateway/`: backend Node mock-only con `GET /health`, `GET /ready` y `POST /v1/chat`.
- `docker-compose.canary.yml`: servicio `ai-gateway` expuesto en `${AI_GATEWAY_PORT:-8095}`.
- `extended_opcode.lua` queda como puente fino entre opcode, validacion, contexto y respuesta.

Revisar:

- `otclient/modules/game_interface/gameinterface.lua`
- `otclient/modules/game_questlog/game_questlog.lua`
- `otclient/modules/game_skills/skills.lua`
- `otclient/modules/game_inventory/inventory.lua`
- `canary-main/src/lua/functions/creatures/player/player_functions.cpp`

Crear:

- `otclient/modules/game_ai_copilot/ai_copilot.otmod`
- `otclient/modules/game_ai_copilot/ai_copilot.lua`
- `otclient/modules/game_ai_copilot/ai_copilot.otui`
- `canary-main/data/libs/ai_copilot/context.lua`
- `canary-main/data/libs/ai_copilot/validator.lua`
- `canary-main/data/scripts/creaturescripts/ai_copilot/extended_opcode.lua`
- `ai-gateway/` con modo mock. El modo Gemini queda documentado como futuro, no implementado todavia.

Flujo de datos:

```text
Jugador pregunta en panel -> OTClient envia ExtendedOpcode -> Canary agrega contexto -> ai-gateway responde -> Canary valida -> OTClient muestra respuesta
```

Riesgos:

- latencia de Gemini;
- cuota gratuita insuficiente;
- prompt injection desde texto del jugador;
- respuestas inventadas si no hay KB;
- bloqueo del hilo del servidor si se hace llamada externa de forma sincrona.

Pruebas minimas:

- gateway mock responde siempre;
- Gemini se puede desactivar con env var;
- timeout devuelve mensaje amable;
- rate limit por jugador;
- clave Gemini no aparece en HTML, JS ni logs publicos.

### Fase 2 - Knowledge Base Curada (En Progreso)

Superficie: servidor + backend.

Objetivo: alimentar respuestas con datos confiables del servidor y no con suposiciones del modelo.

Estado: iniciada. `ai-gateway/kb/` contiene la primera KB versionada con reglas del servidor, ubicaciones, NPCs, hunts tempranas y rutas solo documentales. `ai-gateway/kb.js` carga, valida y recupera coincidencias sin dependencias externas; `server.js` devuelve `cards`, `sources` y metadatos `knowledge` manteniendo `route = null` y `actions = []`. El scoring evita matchear solo por nivel o por palabras genericas, `npm run validate:kb --prefix ai-gateway` valida versiones, IDs, keywords y fuentes locales, y `npm run evaluate:kb --prefix ai-gateway` ejecuta preguntas doradas de retrieval.

Revisar:

- `canary-main/config.lua`
- `canary-main/data-otservbr-global/npc`
- `canary-main/data-otservbr-global/world/otservbr-npc.xml`
- `canary-main/data/scripts`
- `canary-main/schema.sql`

Crear:

- `ai-gateway/kb/server_rules.json`
- `ai-gateway/kb/locations.json`
- `ai-gateway/kb/npcs.json`
- `ai-gateway/kb/hunts.json`
- `ai-gateway/kb/routes.json`
- scripts opcionales de extraccion/validacion.

Implementado:

- `ai-gateway/kb/server_rules.json`: perfil Eldera Online 15 y politica read-only de Copilot.
- `ai-gateway/kb/locations.json`: Dawnport, Rookgaard, Thais, Carlin y Venore.
- `ai-gateway/kb/npcs.json`: The Oracle, Al Dee, Benjamin, Frodo y Xodet.
- `ai-gateway/kb/hunts.json`: notas iniciales para Dawnport, Rookgaard sewers, Troll Cave y rotworms.
- `ai-gateway/kb/routes.json`: entradas documentales sin activar overlay ni movimiento.
- `ai-gateway/kb/evals/golden.json`: preguntas doradas para detectar regresiones de ranking en el retrieval.
- `ai-gateway/kb.js`: validacion y retrieval local para el mock.
- `ai-gateway/scripts/validate-kb.js`: validacion reproducible de la KB y sus referencias a fuentes del repositorio.
- `ai-gateway/scripts/evaluate-kb.js`: evaluacion reproducible de preguntas esperadas contra la KB.

Flujo de datos:

```text
Pregunta + contexto jugador -> retrieval en KB -> prompt acotado -> respuesta con fuente interna -> validacion servidor
```

Riesgos:

- NPC scripts dificiles de extraer automaticamente;
- rutas o zonas desactualizadas;
- KB demasiado grande para contexto barato;
- respuestas sin dato real.

Pruebas minimas:

- validacion JSON schema de cada KB;
- preguntas doradas con respuestas esperadas;
- caso sin informacion devuelve "no tengo ese dato";
- versionado de KB junto al build del servidor.

Comandos actuales:

- `npm test --prefix ai-gateway`
- `npm run validate:kb --prefix ai-gateway`
- `npm run evaluate:kb --prefix ai-gateway`

### Fase 3 - Recomendador Contextual

Superficie: ambos + backend.

Objetivo: recomendar proximos pasos segun estado real del personaje.

Estado: iniciada. `ai-gateway/kb/recommendation_rules.json` define reglas deterministicas y read-only para recomendaciones tempranas; `ai-gateway/recommender.js` selecciona candidatos por intencion, nivel y prioridad; `server.js` devuelve cards de tipo `recommendation` antes de las cards de KB cuando aplica. El panel `game_ai_copilot` renderiza cards informativas con titulo, resumen, razones, cautelas y referencias relacionadas, y los artefactos browser fueron desplegados en `web15/public`. Para recomendaciones normales `route` sigue siendo `null`, `actions` sigue siendo `[]`, Gemini sigue desactivado y todavia no hay tasker ni automatizacion.

Revisar:

- `otclient/modules/game_skills/skills.lua`
- `otclient/modules/game_inventory/inventory.lua`
- `otclient/modules/game_containers/containers.lua`
- `otclient/modules/game_battle/battle.lua`
- `otclient/modules/game_questlog/game_questlog.lua`
- `canary-main/src/lua/functions/creatures/player/player_functions.cpp`

Crear:

- `canary-main/data/libs/ai_copilot/recommender.lua`
- `ai-gateway/kb/recommendation_rules.json`
- UI de cards en `game_ai_copilot`.

Implementado en esta fase:

- `ai-gateway/kb/recommendation_rules.json`: reglas para sewers, Troll Cave, Oracle nivel 8, rotworms cautelosos y suministros basicos.
- `ai-gateway/recommender.js`: scoring deterministico sin proveedor externo.
- `server.js`: cards `recommendation`, metadata `recommender`, sin rutas ni acciones.
- `ai-gateway/kb/evals/golden.json`: casos dorados para recomendaciones, incluyendo nivel 8 -> Oracle y supplies -> Al Dee.
- `otclient/modules/game_ai_copilot/ai_copilot.lua`: render read-only de hasta 3 cards por respuesta.
- `otclient/modules/game_ai_copilot/ai_copilot.otui`: estilos compactos para cards dentro del historial del panel.
- `scripts/repack-otclient-preload.js`: repack enfocado de archivos precargados del modulo Copilot para cambios Lua/OTUI sin recompilar C++/WASM completo.
- `web15/public/otclient.js`, `web15/public/otclient.data` y `web15/public/otclient.wasm`: artefactos browser actualizados desde la imagen `otclient-web:latest`; el paquete servido contiene `CopilotCardPanel` y el source `ai_copilot.lua` coincide por SHA256 con el archivo empaquetado.

Flujo de datos actual:

```text
Jugador pregunta por siguiente paso -> gateway lee contexto -> reglas generan candidatos -> respuesta deterministica con cards -> cliente muestra mensaje/cards disponibles
```

Flujo objetivo posterior:

```text
Cliente pide recomendacion -> servidor calcula estado mas rico -> reglas generan candidatos -> Gemini redacta explicacion acotada -> cliente muestra cards
```

Riesgos:

- recomendar zonas sin acceso por storage/quest;
- ignorar PvP, protection level o supplies;
- usar datos incompletos del cliente;
- recomendaciones demasiado genericas.

Pruebas minimas:

- fixtures por nivel/vocacion;
- caso sin supplies suficientes;
- caso en zona peligrosa o PZ;
- snapshot de cards generadas;
- Gemini caido mantiene recomendacion deterministica basica.

Comandos actuales:

- `npm test --prefix ai-gateway`
- `npm run validate:kb --prefix ai-gateway`
- `npm run evaluate:kb --prefix ai-gateway`
- `node scripts/repack-otclient-preload.js web15/public otclient/build-emscripten-web`

Smoke validado:

- `http://localhost:8082/game/?smoke=ui11-level8` carga `otclient.js?v=canary15-copilot-ui11`, `otclient.data?v=canary15-copilot-ui11` y `otclient.wasm?v=canary15-copilot-ui11`.
- Login con `Druid Noob 1` nivel 8, `Ctrl+J`, pregunta `what should I do next at level 8?`.
- El panel muestra respuesta por ExtendedOpcode con contexto real del personaje y cards renderizadas desde el gateway mock/deterministico.

### Fase 4 - Rutas Y Overlay Visual

Superficie: principalmente cliente, con datos/validacion del servidor.

Objetivo: mostrar rutas y waypoints oficiales sin automatizar todavia.

Estado: iniciada. La primera ruta oficial es `route.rookgaard_oracle`, desde la zona de Seymour en la Rookgaard Academy hasta The Oracle en el piso superior. `ai-gateway/server.js` devuelve un objeto `route` solo para entradas `preview-only`, con `waypoints`, `destination`, `actions: []` y `requiresConfirmation: false`. El cliente dibuja flags temporales y marcadores visuales grandes en el minimap, centra visualmente el minimap en la ruta y muestra una franja compacta con boton `Clear`. Cerrar el panel o desloguear limpia el overlay. No hay autowalk ni acciones.

Revisar:

- `otclient/modules/game_minimap/minimap.lua`
- `otclient/modules/gamelib/ui/uiminimap.lua`
- `otclient/src/client/uiminimap.cpp`
- `otclient/src/client/localplayer.cpp`
- `otclient/src/client/mapview.cpp`
- `otclient/src/client/tile.cpp`

Crear:

- `canary-main/data/ai/routes/*.json` o `ai-gateway/kb/routes.json`
- tipos de respuesta `route` y `route_step`.

Implementado en esta fase:

- `ai-gateway/kb/routes.json`: `route.rookgaard_oracle` pasa a `preview-only` con waypoints oficiales basados en `otservbr-npc.xml`.
- `ai-gateway/server.js`: construye respuesta `route` preview-only y mantiene `actions: []`.
- `ai-gateway/server.test.js`: cobertura para ruta preview-only sin acciones.
- `otclient/modules/game_ai_copilot/ai_copilot.lua`: helper de overlay con flags temporales usando `UIMinimap:addFlag(..., temporary = true)`, marcadores visuales grandes por piso, foco visual del minimap en la ruta, estado y limpieza al cerrar panel o desconectar.
- `otclient/modules/game_ai_copilot/ai_copilot.otui`: franja `Route preview` con boton `Clear`.

Flujo de datos:

```text
Jugador pide ruta -> servidor/gateway elige destino -> servidor devuelve waypoints -> cliente dibuja marcadores en minimap -> usuario camina manualmente
```

Riesgos:

- cambios de piso;
- minimap incompleto;
- waypoints obsoletos;
- overlay tapando informacion del juego;
- `Tile:setFill` puede ocultar dibujo normal del tile.

Pruebas minimas:

- ruta en mismo piso;
- ruta multi-floor;
- limpiar overlay al cerrar panel/desconectar;
- zoom/minimap no rompe marcadores;
- destino invalido devuelve error util.

Comandos actuales:

- `npm test --prefix ai-gateway`
- `npm run validate:kb --prefix ai-gateway`
- `npm run evaluate:kb --prefix ai-gateway`
- `node scripts/repack-otclient-preload.js web15/public otclient/build-emscripten-web`

Prueba manual esperada:

- Abrir `http://localhost:8082/game/?smoke=ui13-route`.
- En el panel Copilot preguntar `show me the route to the oracle in Rookgaard`.
- El panel debe mostrar una respuesta de Fase 4, una card `Route info`, una franja `Route preview` y marcadores temporales en el minimap.
- El boton `Clear`, cerrar el panel o desloguear debe limpiar los marcadores.

### Fase 5 - Acciones Guiadas Semi-Automaticas

Superficie: ambos.

Objetivo: permitir acciones confirmables y acotadas: caminar a waypoint, abrir quest tracker, marcar mapa, comprar/vender items permitidos.

Revisar:

- `otclient/src/client/localplayer.cpp`
- `otclient/meta.lua`
- `otclient/modules/game_npctrade/npctrade.lua`
- `otclient/modules/game_interface/gameinterface.lua`
- `canary-main/src/lua/functions/creatures/player/player_functions.cpp`

Crear:

- `otclient/modules/game_ai_copilot/task_runner.lua`
- `canary-main/data/libs/ai_copilot/task_manager.lua`
- whitelist de acciones permitidas;
- permisos por feature flag/cuenta/personaje.

Flujo de datos:

```text
Intencion -> plan estructurado -> servidor valida -> cliente muestra confirmacion -> usuario acepta -> cliente ejecuta paso -> servidor revalida estado
```

Riesgos:

- parecer bot externo si se automatiza demasiado pronto;
- loops de movimiento;
- acciones durante combate, death, PZ lock o trade incorrecto;
- abuso economico;
- desync entre cliente y servidor.

Pruebas minimas:

- cancelacion en cualquier paso;
- dry-run de plan;
- bloqueo si hay combate o estado inseguro;
- confirmacion obligatoria para compras/ventas;
- limite de reintentos y timeout.

### Fase 6 - Tasker Oficial Integrado

Superficie: servidor + cliente + web/admin.

Objetivo: convertir el asistente en un sistema oficial, gobernado por politicas del servidor y visible para administracion.

Revisar:

- `myaac-15.xx/templates/kathrine/template.php`
- `myaac-15.xx/panel-session.php`
- `web/server.js`
- `canary-main/schema.sql`
- logs de `canary-main/logs`

Crear:

- panel admin MyAAC para IA;
- tablas de auditoria y quotas;
- politicas por cuenta/personaje;
- kill switch global;
- reportes de acciones y errores.

Flujo de datos:

```text
Admin configura politicas -> jugador opt-in -> Copilot ejecuta tareas permitidas -> servidor audita -> admin revisa metricas/incidentes
```

Riesgos:

- balance del servidor;
- fairness entre jugadores;
- multi-account abuse;
- privacidad de datos del jugador;
- soporte operativo y moderacion.

Pruebas minimas:

- migraciones DB;
- auditoria completa por task;
- rate limits bajo carga;
- desactivar IA en caliente;
- rollback de politicas;
- pruebas con varios jugadores simultaneos.

## Primer Sprint Recomendado

1. Elegir y documentar `AI_COPILOT_OPCODE`.
2. Crear `game_ai_copilot` con miniwindow, input e historial.
3. Enviar un mensaje dummy por ExtendedOpcode.
4. Crear puente Lua en Canary que responda echo con contexto minimo del jugador.
5. Mostrar la respuesta mock en el panel.

Fuera del primer sprint: Gemini, gateway real, rutas visuales y tasker. La KB minima debe prepararse desde el inicio de la siguiente iteracion: 3 zonas, 3 NPCs, rates, reglas y 5 preguntas doradas.

Definition of done del primer sprint:

- un jugador online puede abrir Eldera Copilot;
- puede preguntar algo simple;
- el servidor recibe la pregunta por ExtendedOpcode;
- el servidor agrega contexto minimo;
- Canary responde echo/mock sin Gemini ni gateway;
- el cliente muestra respuesta;
- no hay secretos en el cliente;
- `requestId` permite correlacionar request y respuesta.

## Politicas De Seguridad Y Costo

- La clave de Gemini vive solo en `ai-gateway` o variables de entorno del backend.
- Nunca enviar password, session key ni tokens al gateway.
- Sanitizar nombre de personaje, texto libre y cualquier texto generado por usuario.
- Limitar requests por minuto y por dia.
- Mantener fallback mock/offline para desarrollo.
- Cachear respuestas de KB cuando sea posible.
- No ejecutar acciones generadas por texto libre.
- Toda accion necesita tipo conocido, parametros validados y confirmacion si afecta movimiento, items o dinero.

## Archivos A Evitar Como Fuente De Verdad

- `web15/public/otclient.js`: artefacto compilado y muy grande.
- `web15/public/index.html`: shell generado/adaptado; util para diagnostico, no para logica principal del cliente.
- `proxy/server.js`: debe seguir como puente raw WebSocket/TCP, no como backend de IA.

## Matriz Minima De Pruebas

| Area | Prueba minima |
| --- | --- |
| ExtendedOpcode | request valido, request invalido, payload grande, jugador desconectado |
| Gateway | mock, Gemini off, timeout, error 429, error 500 |
| Contexto | nivel/vocacion/posicion correctos, sin datos sensibles |
| UI | abrir/cerrar panel, historial, estado cargando, error visible |
| KB | schema valido, dato faltante, respuestas doradas |
| Rutas | mismo piso, multi-floor, limpiar overlay, destino invalido |
| Acciones | confirmacion, cancelacion, bloqueo por estado inseguro, audit log |

## Decision Central

La primera etapa debe ser **read-only, contextual y server-authoritative**. Eldera Copilot puede sentirse inteligente desde el primer sprint sin tomar control del personaje. Las rutas visuales vienen despues, y las acciones solo cuando existan KB, validadores, auditoria y politicas claras.