# Registro de capacidades · front-colportores-mobile

> Tope: 300 líneas. Armado leyendo `origin/develop` en 359f1fa4 (04/11). Cada ruta se verificó contra el árbol. Lo que está en un PR abierto y no en develop dice «PR #N».

**Para qué sirve.** Antes de escribir código, buscá acá por vista (`06`, `39`…), por HU o por palabra (`mapa`, `hoja`, `GPS`). Si lo que necesitás ya está, lo usás. Si hay que cambiarlo, lo cambiás en su lugar y lo decís en el PR. Si no está, lo creás y sumás su entrada en el mismo PR.
**Si el registro y el código no coinciden, manda el código**, y en tu PR corregís la entrada.
Cada entrada tiene `dónde` (archivo), `uso` (3 líneas como máximo), `no duplicar` y `tags` (vistas y HU, con los que se eligen las entradas del briefing).

## Política (decidida por Cristian, 04/11)

1. **Un solo mapa general**: `MapaUbicacionesPage` sobre `MapaBase` (MAPA-01, MAPA-02). Todo lo demás son hojas, modos o capas encima de ese mapa. Un mapa nuevo necesita una decisión §3.
2. **El permiso de GPS se pide solo desde el mapa.** Ninguna otra pantalla dispara el diálogo del sistema (PERM-01).
3. **Un solo alta de ubicación**: `altaUbicacionProvider` (FLUJO-06). El pin del mapa es otra forma de entrar, no otro alta.
4. **Mantenimiento**: todo PR que agrega o cambia una capacidad actualiza su fila en el mismo PR. El revisor lo exige.

## Deuda conocida (no se arregla con este registro)

| Deuda | Dónde | Entrada |
|---|---|---|
| 5 sitios con `MapaBase(`: pestaña Mapa, alta (03), modificar (07) y 2 mini-mapas (04 y 10) | `mapa_ubicaciones_page`, `mapa_alta`, `mapa_modificar`, `hoja_duplicado_alta`, `hoja_comparar_duplicado` | MAPA-08 |
| 9 copias privadas de `_Asa` (más `_AsaDeLaLista` en `mostrar_hoja_casa.dart`) | las 9 hojas listadas en HOJA-04 | HOJA-04 |
| 3 enchufes de la hoja de la casa sin conectar en `main.dart` | `entrevistaDadaDesdeLaCasaProvider`, `fichaDePersonaDesdeLaCasaProvider`, `pestanaHistorialDeLaCasaProvider` | CASA-02 |
| Precios pide el permiso de GPS (contra la política 2) | `catalogo/presentation/providers/precios_providers.dart:104` | PERM-01 |

---

## NAV · Estructura y navegación

### NAV-01 · Pantalla principal con 6 pestañas: `InicioPage`
- dónde: `lib/features/inicio/presentation/pages/inicio_page.dart` · barra: `inicio/presentation/widgets/barra_pestanas_inicio.dart` (`PestanaInicio`)
- uso: `IndexedStack` con Hoy · Mapa · Lista · Agenda · Ventas · Cuenta, que se mantienen vivas. Arriba van la campana y el engranaje, y debajo `_FranjaDeAvisos`. Una pantalla empujada que tiene su propia barra (Configuración, Precios) devuelve la `PestanaInicio` elegida.
- no duplicar: ninguna pantalla nueva arma su propio `Scaffold` con barra inferior. Un aviso nuevo de Inicio va en `_FranjaDeAvisos`.
- tags: vistas 00 06 16 26 33 · HU-JOR-001 HU-UBI-002 HU-UBI-003 HU-VIS-002 HU-CTA-001

### NAV-02 · Navegación sin router
- dónde: `lib/app.dart` (`navigatorKeyColportores`, `routeObserverColportores`, `home:` según sesión) · cada página expone `static abrir(context, …)` o `static ruta(…)`
- uso: `await FichaPersonaPage.abrir(context, …)` devuelve la salida tipada (`SalidaAltaUbicacion`, `bool`, `VentaGuardada`…). No hay `go_router`: los comentarios que lo anuncian «para Sprint 5» quedaron viejos.
- no duplicar: nada de `go_router`, rutas con nombre ni un segundo `Navigator`. Cambiar eso es una decisión §3.
- tags: todas

### NAV-03 · Arranque y portones (antes de Inicio)
- dónde: `lib/app.dart` (`_Principal`, línea ~386 `PedidoPermisoNotificacionesPage`) · `auth/presentation/pages/*` (login, 13, 18) · `respaldo/presentation/pages/recuperacion_page.dart` (34)
- uso: el orden es login, base local (13), recuperación (34), permiso de notificaciones (24A), esperando asignación (18) e Inicio. La cuenta restringida se avisa con `avisarCuentaRestringida`.
- no duplicar: un pedido de primer ingreso va en esta cadena, nunca en una pestaña.
- tags: vistas 12-18 24 34 · HU-AUTH-* HU-NOT-001 HU-SYNC-006

### NAV-04 · Enchufes entre features (`…DesdeLaCasaProvider`)
- dónde: el enchufe se define en la feature que muestra el botón, con `null` por defecto (ej. `mapa/presentation/providers/hoja_casa_providers.dart`), y se conecta con `overrideWith` en `lib/main.dart` (líneas ~273-380)
- uso: `ref.watch(cobrarDesdeLaCasaProvider)`: si es `null`, el botón no se dibuja (HU-UBI-003). Para conectar una acción, el PR agrega el `override` en `main.dart`, que llama al `Flujo…abrir` o `…Page.abrir` del destino.
- no duplicar: un widget no importa la página de otra feature para abrirla directo, y ningún enchufe queda sin `override` (hoy pasa con 3, ver CASA-02).
- tags: vistas 23 27 28 31 32 39

## MAPA · El mapa único y sus capas

### MAPA-01 · Mapa base: `MapaBase` (MapLibre)
- dónde: `lib/features/mapa/presentation/mapa_base/mapa_base.dart` · modelo: `mapa_base/modelo_mapa_base.dart` (`PuntoMapa`, `EstiloPunto`, `CirculoPrecision`, `CirculoCercania`, `InteraccionMapa`, `ControladorMapaBase`, `ColoresMapa`) · nativo: `mapa_base/vista_maplibre.dart`
- uso: `MapaBase(fuente: …, camaraInicial: … | ajuste: AjusteMapa(puntos: …), puntos: […], zonas: …, alTocarPunto: …, alTocarLargo: …, alCrearse: (c) => _mapa = c)`. La cámara se mueve con el `ControladorMapaBase`. Puntos, zonas y precisión son capas del estilo, no widgets.
- no duplicar: nunca `MapLibreMap(` fuera de `vista_maplibre.dart`, y nunca otro mapa a pantalla completa para algo que pasa «sobre el mapa»: eso va en MAPA-02.
- tags: vistas 03 04 06 07 10 39 · HU-UBI-001 HU-UBI-003

### MAPA-02 · Pestaña Mapa: `MapaUbicacionesPage`, el ÚNICO mapa de trabajo
- dónde: `lib/features/mapa/presentation/pages/mapa_ubicaciones_page.dart` · estado: `mapaUbicacionesProvider(colportorId)` (`providers/mapa_ubicaciones_notifier.dart`, con `hayVistaPrevia`) · ámbito: `ambitoMapaUbicacionesProvider` (`providers/mapa_ubicaciones_providers.dart`) · hoja de abajo: `HojaMapaUbicaciones` y `AlturaHoja` (`widgets/hoja_mapa_ubicaciones.dart`)
- uso: lo que se agrega «sobre el mapa» (un pin, un aviso fijo, un botón, la hoja de la casa) entra en el `Stack` de esta página o como capa de MAPA-01. El GPS se pide la primera vez que se abre la pestaña. El pin que se arrastra para dar de alta (N·01 a N·03) está en el PR #477 (`widgets/pin_nueva_casa.dart`, seam `alConfirmarPosicion`), todavía no en develop.
- no duplicar: no se crean pantallas con mapa propio para acciones de la calle. Si una vista nueva «necesita el mapa», usa esta pestaña: se cambia a `PestanaInicio.mapa`, que es lo que hace `JornadaPage(onAbrirMapa:)`.
- tags: vistas 06 39 · HU-UBI-003 HU-VIS-001 HU-VIS-005

### MAPA-03 · Tiles, estilo y recursos
- dónde: `mapa/presentation/providers/mapa_base_providers.dart` (`fuenteMapaProvider(AmbitoTrabajo)`, `constructorVistaMapaProvider`) · `mapa_base/recursos_mapa_providers.dart` (`recursosMapaProvider`) · `mapa_base/estilo_mapa.dart` · `AmbitoTrabajo` en `tiles/domain/entities/paquete_tiles.dart`
- uso: `MapaBase(fuente: ref.watch(fuenteMapaProvider(ambito)))`. Elige primero el PMTiles descargado, si no el online y si no nada. En los tests, `constructorVistaMapaProvider` se reemplaza por la vista falsa (TEST-01).
- no duplicar: no se leen PMTiles ni se arma un estilo por fuera de esto. Para descargar mapas, `MapasOfflinePage.ruta()` (vista 35).
- tags: vistas 06 35 · HU-SYNC-010 ADR-011

### MAPA-04 · Marcadores por estado, cuadrados con número, toque y leyenda
- dónde: `mapa_base/marcador_estado.dart` (8 estados más el edificio) · `mapa/domain/services/cuadrados_del_mapa.dart` (`CuadradosDelMapa`) · `mapa_base/marcador_cercano.dart` · `mapa_base/seleccion_toque.dart` · leyenda: `mostrarReferenciasMapa` (`widgets/piezas_mapa_ubicaciones.dart`)
- uso: el color sale de `house_status` (DATO-02) y nunca se calcula al abrir el mapa. Los cuadrados aparecen solo cuando entran todos en pantalla (decisión del 23/10).
- no duplicar: ningún otro mapa de colores ni otro marcador. Un estado nuevo se suma en `marcador_estado.dart`.
- tags: vistas 05 06 39 · HU-VIS-005 ADR-003

### MAPA-05 · Zonas de la campaña sobre el mapa
- dónde: `mapa/presentation/providers/zonas_del_mapa_providers.dart` (`zonasParaElMapaProvider(colportorId)`) · `mapa_base/zonas_mapa.dart` (`ZonaMapa`)
- uso: `MapaBase(zonas: ref.watch(zonasParaElMapaProvider(id)).zonas)`. Van por debajo de los puntos y no reciben toques. Si la lectura falla, el mapa sigue con las zonas que ya tenía.
- no duplicar: la zona se calcula con `ubicadorZonaProvider` (DATO-05), no a mano.
- tags: vistas 06 36 · HU-CAM-006 · #511

### MAPA-06 · Cámara, proyección y coordenadas
- dónde: `mapa/domain/services/proyeccion_mercator.dart` (`ProyeccionMercator.zoomDeFlutterMap`, `aPantalla`) · `mapa/domain/value_objects/` (`CamaraMapa`, `AreaMapa`, `Coordenadas`)
- uso: para poner un widget sobre un punto, `ProyeccionMercator.aPantalla(punto, camara, ancho, alto)`. Los zooms del canvas se pasan con `zoomDeFlutterMap` (las teselas son de 512 px).
- no duplicar: nada de cuentas de Mercator ni de zooms escritos a mano.
- tags: vistas 03 06 07 39

### MAPA-07 · Aviso del mapa: offline, mapa caído, sin conexión
- dónde: `mapa/presentation/widgets/aviso_mapa.dart` (`AvisoMapaConectado`, `AvisoMapaModo`) · `providers/situacion_mapa_providers.dart` (`situacionMapaProvider`, `avisoMapaVisibleProvider`, `descartesAvisoMapaProvider`)
- uso: `AvisoMapaConectado(...)` arriba del mapa. No tapa toques fuera de sí y ya trae las tarjetas 06C·05 y 06C·06 (sin conexión).
- no duplicar: ninguna tarjeta propia de «sin mapa» o «sin conexión» sobre un mapa.
- tags: vistas 03 06 07 35 · HU-SYNC-010 · #299

### MAPA-08 · Mapas acotados que ya existen (DEUDA CONOCIDA: la lista se cierra acá)
- dónde: `widgets/mapa_alta.dart` (`MapaAlta`, pantalla 03) · `widgets/mapa_modificar.dart` (`MapaModificar`, 07, con el «fantasma» del punto de antes) · los mini-mapas de `widgets/hoja_duplicado_alta.dart` (04) y `widgets/hoja_comparar_duplicado.dart` (10)
- uso: hay 5 sitios con `MapaBase(` en develop, y 3 son a pantalla completa (06, 03 y 07). Con la 39, el alta pasa al pin de MAPA-02 (PR #477), y la pantalla 03 queda solo como formulario (a confirmar desde la Lista).
- no duplicar: **un mapa nuevo necesita una decisión §3.** Este registro no admite un sexto.
- tags: vistas 03 04 07 10 39

## PERM · Permisos y dispositivo

### PERM-01 · GPS: lectura y permiso (DEUDA CONOCIDA: Precios lo pide)
- dónde: `mapa/presentation/providers/alta_ubicacion_providers.dart` (`plataformaGpsProvider`, `proveedorGpsProvider`, `activadorGpsProvider`, `capturarPosicionGpsUseCaseProvider`) · adaptador: `mapa/data/services/proveedor_gps_plataforma.dart` · puerto: `mapa/domain/services/proveedor_gps.dart`
- uso: `ref.read(proveedorGpsProvider).posicionActual()` lee la posición y **pide el permiso si está denegado** (línea 36). Para saber si hay permiso sin pedirlo, `ref.read(plataformaGpsProvider).permiso()`. Por política, el permiso se pide solo desde el mapa.
- no duplicar: nada de `Geolocator` directo (solo `plataforma_gps_geolocator.dart`). Hoy llegan a `posicionActual()` el Mapa, la Lista, el Alta, Modificar (por `capturarPosicionGpsUseCaseProvider`) **y Precios**, directo en `catalogo/presentation/providers/precios_providers.dart:104`: eso contradice la política y se arregla en un issue aparte.
- tags: vistas 03 05 06 26 · HU-UBI-001 HU-UBI-003 HU-CAT-006

### PERM-02 · Notificaciones: un solo puerto
- dónde: `notificaciones/presentation/pages/pedido_permiso_notificaciones_page.dart` (24A·01, primer ingreso) · `features/notificaciones/presentation/providers/notificaciones_providers.dart` (`notificacionesProvider`, `permisoNotificacionesRepositoryProvider`) · el puerto del sistema: `lib/core/notificaciones/notificaciones_providers.dart` (`permisoNotificacionesSistemaProvider`, `permisoAlarmasExactasProvider`) · `alarmas_exactas_providers.dart` · aviso en Hoy: `widgets/aviso_notificaciones.dart`
- uso: el permiso se pide una sola vez en NAV-03. Después solo se lee el estado, y para volver a encenderlas se manda a los ajustes del sistema (PERM-03).
- no duplicar: ningún `requestPermission` de notificaciones fuera de este puerto (lo dice HU-NOT-001). Ojo con los dos archivos de nombre parecido: el de `core/` es el puerto, el de `features/` es el repositorio.
- tags: vistas 24 · HU-NOT-001 HU-NOT-002 HU-NOT-003

### PERM-03 · Ajustes del sistema, conectividad y dispositivo
- dónde: `core/dispositivo/abridor_ajustes_sistema.dart` (`abridorAjustesSistemaProvider`) · `core/conectividad/conectividad_providers.dart` (`monitorConectividadProvider`) · `core/dispositivo/dispositivo_providers.dart` · `core/dispositivo/marcador_de_telefono_canal.dart` (llamar)
- uso: `ref.read(abridorAjustesSistemaProvider)` lleva a los ajustes. `monitorConectividadProvider` dice si hay red. La UI de «sin conexión» se arma con AVISO-01.
- no duplicar: ningún canal de plataforma nuevo para estas cosas.
- tags: vistas 06 16 24 25

## CASA · La casa en el mapa (vista 39)

### CASA-01 · Hoja de la casa: `HojaCasa`
- dónde: `mapa/presentation/widgets/hoja_casa.dart` · en el mapa: dentro de `HojaMapaUbicaciones` (`hoja_mapa_ubicaciones.dart:209`) · desde la Lista: `mostrarHojaCasa(context, colportorId:, item:)` (`widgets/mostrar_hoja_casa.dart`) · datos: `contextoDeLaCasaProvider(ClaveDeLaCasa)` (`providers/hoja_casa_providers.dart`) · pestañas: `pestanas_hoja_casa.dart`, `pestana_notas_de_la_casa.dart` · estados: `estados_hoja_casa.dart`
- uso: la misma hoja sirve en el mapa y en la Lista. C·01 es el resumen y C·02 la hoja arriba, con Personas, Historial y Notas. Todo lo que se registra en la calle sale de acá.
- no duplicar: ninguna «vista previa» ni ficha de casa nueva. Una acción nueva entra como botón con enchufe (CASA-02).
- tags: vistas 05 06 39 · HU-UBI-003 HU-VIS-001 HU-VIS-005 HU-COB-005

### CASA-02 · Enchufes de la hoja de la casa (DEUDA CONOCIDA: 3 sin conectar)
- dónde: `mapa/presentation/providers/hoja_casa_providers.dart` (typedefs `ContextoDeVisita`, `ContextoDeCobro`, `ContextoDeCita`, `ContextoDeEntrevista`, `ContextoDeFicha`, `ContextoDeDevolucion`, `ContextoDePestana`) · override en `lib/main.dart`
- uso: conectados en develop: `registrarVisitaDesdeLaCasaProvider` (FLUJO-00), `programarEntrevistaDesdeLaCasaProvider` (FLUJO-01), `cobrarDesdeLaCasaProvider` (FLUJO-04), `devolverVentaDesdeLaFichaProvider` y `pestanaNotasDeLaCasaProvider`. **Sin conectar**: `entrevistaDadaDesdeLaCasaProvider` («Entrevista dada» no aparece), `fichaDePersonaDesdeLaCasaProvider` (`FichaPersonaPage.abrir` no tiene quién la llame) y `pestanaHistorialDeLaCasaProvider`. Tampoco tiene `override` `editarPersonaDesdeLaFichaProvider` (`providers/ficha_persona_providers.dart`).
- no duplicar: lo que recibe un destino ya viene resuelto en su typedef (casa, depto, persona), así que la vista hija no lo vuelve a pedir.
- tags: vistas 23 27 28 31 32 39

### CASA-03 · Ubicación con deptos (vista 11) y personas del espacio
- dónde: `widgets/hoja_ubicacion.dart` (`mostrarHojaUbicacion`) · `widgets/hoja_depto.dart` (`mostrarHojaDepto`, `SalidaHojaDepto`) · `pages/personas_del_espacio_page.dart` (sin quién la llame en develop)
- uso: un edificio o un negocio de la Lista abre `mostrarHojaUbicacion` (en `InicioPage._abrirUbicacion`). En un edificio el contexto es siempre el depto (`espacio_id`).
- no duplicar: ninguna lista de deptos propia.
- tags: vistas 11 39 · HU-UBI-007

### CASA-04 · «¿Con quién?» y alta corta de persona
- dónde: `widgets/hoja_con_quien.dart` (`mostrarHojaConQuien` → `PersonaDeLaEntrevista`, `mostrarHojaConQuienParaProgramar` → `EleccionDeCita`) · `pages/alta_persona_page.dart` (`AltaPersonaPage.abrir` → `Persona`)
- uso: con una sola persona se salta el paso. «+ Alguien nuevo» abre `AltaPersonaPage` y vuelve al paso en el que estaba.
- no duplicar: ningún selector de persona propio, ni siquiera desde la Agenda (FLUJO-01 ya lo reusa).
- tags: vistas 23 32 39 · HU-UBI-008

## FLUJO · Flujos que encadenan pantallas (se abren con `Flujo….abrir`)

### FLUJO-00 · Registrar visita: «¿Qué pasó?»
- dónde: `mapa/presentation/flujo_registrar_visita.dart` (`FlujoRegistrarVisita.abrir`) · `widgets/hoja_que_paso.dart` (`mostrarHojaQuePaso`, `OpcionQuePaso`) · textos: `textos_registrar_visita.dart`
- uso: «No contestó» y «Rechazo» se guardan de un toque y dan «Deshacer». Las otras opciones siguen por sus enchufes. La Agenda lo reusa con `agendaId` (`agenda_page.dart:172`, `detalle_agenda_page.dart:129`).
- no duplicar: no hay otra pantalla de «resultado de la visita»: la 23D quedó reemplazada por la 39.
- tags: vistas 23 39 · HU-VIS-001 HU-VIS-005

### FLUJO-01 · Agendar (entrevista o cobranza)
- dónde: `agenda/presentation/flujo_agendar_visita.dart` (`FlujoAgendarVisita.abrir` → `AgendarVisitaPage`) · `mapa/presentation/flujo_agendar_desde_la_agenda.dart` (elige la casa con `ElegirCasaParaAgendarPage`, que es la Lista con `paraElegir: true`) · día y hora: `mostrarHojaDiaYHora` (`agenda/presentation/widgets/piezas_agendar_visita.dart`)
- uso: lo llaman la 39, la Agenda, el cobro y las cuotas. Deja el aviso de éxito en el `ScaffoldMessenger` de quien lo abrió.
- no duplicar: ningún formulario de agenda ni selector de fecha y hora propio.
- tags: vistas 23 28 30 39 · HU-VIS-002 HU-VIS-006

### FLUJO-02 · Entrevista en curso
- dónde: `agenda/presentation/widgets/flujo_entrevista.dart` (`FlujoEntrevista.abrir`) · aviso fijo del mapa: `agenda/presentation/widgets/aviso_entrevista_en_curso.dart` · `hoja_entrevista_en_curso.dart`, `hoja_termino_entrevista.dart`
- uso: va de R·05 a R·07. «Sí, registrar la venta» sigue a FLUJO-03 con la casa, la persona y la visita ya puestas.
- no duplicar: el inicio y el fin de la entrevista no se registran en otro lado.
- tags: vistas 21 27 39 · HU-VIS-005 · #450

### FLUJO-03 · Venta y «¿Cuándo volvés a cobrar?»
- dónde: `ventas/presentation/pages/nueva_venta_page.dart` (`NuevaVentaPage.ruta` → `VentaGuardada`) · `ventas/presentation/flujo_cuando_cobrar.dart` (`FlujoCuandoCobrar`) · `cobrarDespuesDeLaVentaProvider` (`ventas_providers.dart`) · `widgets/selector_de_productos.dart`, `hoja_elegir_libro.dart`
- uso: hoy la abre FLUJO-02. La pestaña Ventas sigue en `PestanaProvisoria` en develop (el PR #625, abierto, la conecta).
- no duplicar: ningún selector de productos ni precio de venta propio (precios: `preciosDeLaVentaProvider`).
- tags: vistas 26 27 · HU-VEN-001 HU-VEN-002 HU-VEN-003

### FLUJO-04 · Cobro desde la casa
- dónde: `cobranzas/presentation/flujo_cobrar_desde_la_casa.dart` (`FlujoCobrarDesdeLaCasa.abrir`) · `cobranzas/presentation/widgets/hoja_que_venta.dart` (`mostrarHojaQueVenta`) · `pages/cobro_efectivo_page.dart`, `plan_de_cuotas_page.dart`, `cuotas_de_la_venta_page.dart`
- uso: con una sola venta con saldo va directo. No escribe la visita: la escribe FLUJO-00 si vuelve `true`.
- no duplicar: ningún saldo calculado a mano (`saldoDeLaVentaProvider`, `saldoDeLaPersonaProvider` en `cobranzas_providers.dart`).
- tags: vistas 28 29 30 39 · HU-COB-001 HU-COB-004 HU-COB-005

### FLUJO-05 · Persona: ficha, notas, devolución
- dónde: `mapa/presentation/pages/ficha_persona_page.dart` (`FichaPersonaPage.abrir`) · `notas_de_persona_page.dart`, `nota_persona_form_page.dart` · `ventas/presentation/pages/devolucion_page.dart` (`DevolucionPage.abrir`, por `devolverVentaDesdeLaFichaProvider`) · `widgets/hoja_baja_persona.dart`
- uso: se entra desde la pestaña Personas de CASA-01, con el enchufe `fichaDePersonaDesdeLaCasaProvider`, que **falta conectar** (CASA-02).
- no duplicar: ninguna ficha ni historial de persona propio.
- tags: vistas 31 32 39 · HU-UBI-008 a HU-UBI-012 HU-VEN-004 HU-VEN-005

### FLUJO-06 · Alta, modificación y baja de una ubicación (UN solo alta)
- dónde: `pages/alta_ubicacion_page.dart` (`AltaUbicacionPage.abrir` → `SalidaAltaUbicacion`) · `providers/alta_ubicacion_notifier.dart` (`altaUbicacionProvider`, que también usa el pin del PR #477 con `puntoInicial`) · `widgets/hoja_alta.dart`, `campos_ubicacion.dart` · duplicado: `mostrarHojaDuplicado` · `pages/modificar_ubicacion_page.dart` · `mostrarHojaBaja`, `mostrarHojaReactivar`
- uso: las reglas de 03 y 04 (duplicado a 5 m, dirección única a 100 m) viven en el notifier y en el dominio. Cualquier forma de dar de alta pasa por `altaUbicacionProvider`.
- no duplicar: ningún notifier de alta nuevo. El alta por pin es otra forma de **entrar**, no otro alta.
- tags: vistas 03 04 07 09 39 · HU-UBI-001 HU-UBI-004 HU-UBI-005

### FLUJO-07 · Jornada
- dónde: `jornada/presentation/providers/jornada_actual_notifier.dart` (`jornadaActualProvider(colportorId)`: `iniciar`, `finalizar`) · `pages/jornada_page.dart` (`onAbrirMapa`) · `widgets/hoja_hora_inicio.dart`
- uso: las visitas llevan el `jornada_id` de la jornada abierta de hoy (FLUJO-00, #475).
- no duplicar: nadie más lee la jornada «de hoy» por su cuenta.
- tags: vistas 20 21 · HU-JOR-001 HU-JOR-002 HU-JOR-003

## HOJA · Hojas, avisos y piezas de UI

### HOJA-01 · Hoja inferior con teclado y medida
- dónde: `mapa/presentation/widgets/medida_hoja.dart` (`HojaInferior`, `MedidaDeLaHoja`, `NecesidadHoja`)
- uso: es la hoja que sube con el teclado sin tapar el mapa. La usan el alta y la modificación.
- no duplicar: antes de calcular `viewInsets` a mano, mirá esto.
- tags: vistas 03 07 39

### HOJA-02 · Aviso con «Deshacer»
- dónde: `mapa/presentation/widgets/aviso_con_deshacer.dart` (`mostrarAvisoConDeshacer`, `AvisoDeshacerEnHoja` para adentro de una hoja)
- uso: dura 8 s y con un lector de pantalla no se cierra solo (WCAG 2.2.1).
- no duplicar: ningún `SnackBar` propio con «Deshacer».
- tags: vistas 09 39 · R·01

### HOJA-03 · Selectores de fecha, hora y ciudad
- dónde: `mostrarHojaDiaYHora`, `mostrarHojaHoraPasada` (`agenda/presentation/widgets/piezas_agendar_visita.dart`) · `mostrarHojaHoraInicio` (jornada) · `mostrarHojaFechaDelCobro` (`cobranzas/presentation/widgets/piezas_cobro.dart`) · ciudad: `mostrarHojaCiudad` (`mapa/presentation/widgets/hoja_ciudad.dart`, alta 03) y `mostrarHojaOtraCiudad` (`catalogo/presentation/widgets/hoja_otra_ciudad.dart`, 26·04)
- uso: ya hay **dos** selectores de ciudad, con diseños distintos. Antes de hacer un tercero, se usa uno de estos.
- no duplicar: ningún selector de fecha, hora o ciudad nuevo sin decirlo en el PR.
- tags: vistas 03 20 23 26 28

### HOJA-04 · Asa de hoja (DEUDA CONOCIDA: 9 copias)
- dónde: hoy hay **9 copias privadas `_Asa`**: `hoja_entrevista_en_curso`, `hoja_termino_entrevista`, `hoja_que_venta`, `hoja_hora_inicio`, `hoja_comparar_duplicado`, `hoja_con_quien`, `hoja_filtros_lista`, `hoja_mapa_ubicaciones` y `hoja_que_paso`. Además `_AsaDeLaLista` en `mostrar_hoja_casa.dart`.
- uso: para una hoja nueva, se copia de `hoja_que_paso.dart`, que es la más reciente.
- no duplicar: una copia más no. Extraer `AsaDeHoja` queda como issue aparte (a confirmar).
- tags: vistas 23 26 39

## AVISO · Errores, avisos y tema

### AVISO-01 · Texto del error y «sin conexión»
- dónde: `core/presentation/mensaje_para.dart` (`mensajePara(failure, accion:, noPudimos:)`, `mensajeDeServidor`) · widgets **compartidos que viven en auth**: `auth/presentation/widgets/banner_error_con_accion.dart`, `texto_error_anunciado.dart`, `icono_sin_conexion.dart`
- uso: `mensajePara(f, accion: 'registrar la visita')` arma «Necesitás conexión para registrar la visita». `TextoErrorAnunciado` lo anuncia al lector de pantalla.
- no duplicar: ningún texto de «sin conexión» suelto ni un banner de error propio.
- tags: todas · convenciones §10

### AVISO-02 · Franja de avisos de Inicio
- dónde: `auth/presentation/widgets/aviso_zona_banner.dart` (`AvisoZonaBanner`, 36) · `respaldo/presentation/widgets/aviso_sin_respaldo.dart` (`AvisoSinRespaldo`) · `notificaciones/presentation/widgets/aviso_notificaciones.dart`, `aviso_notificaciones_apagadas.dart`
- uso: los aloja `_FranjaDeAvisos` de NAV-01, que tiene un tope de alto conjunto (QA #185).
- no duplicar: un aviso persistente nuevo va en esa franja, no arriba de cada pestaña.
- tags: vistas 24 34 36 · HU-CAM-006 HU-SYNC-005 HU-NOT-001

### AVISO-03 · Tema y colores
- dónde: `core/theme/tema_colportaje.dart`, `core/theme/colores_colportaje.dart` · los del mapa: `ColoresMapa` (`mapa_base/modelo_mapa_base.dart`)
- no duplicar: ningún color escrito a mano si ya existe en el tema o en el canvas.
- tags: todas

## DATO · Datos locales, sync y servidor

### DATO-01 · Base local (Drift, cifrada)
- dónde: `lib/core/database/app_database.dart` (38 tablas: Jornadas, Ubicaciones, Espacios, Personas, EspacioPersonas, Notas, Agendas, Visitas, HouseStatuses, Ventas, VentaItems, Cobranzas, Entregas, Devoluciones, Depositos, Tickets, catálogo, zonas, sync…) · pasos: `app_database.steps.dart`
- uso: si una tabla cambia, se migra y se corre la suite completa (briefing común). Toda migración preserva los datos.
- no duplicar: ninguna tabla nueva para algo que ya tiene la suya (por ejemplo, las notas son una sola tabla, `Notas`, con `target_type`).
- tags: esquema-datos.md

### DATO-02 · `house_status` (el color de la casa)
- dónde: `mapa/presentation/providers/house_status_providers.dart` (`houseStatusUpdaterProvider`)
- uso: es **lo único** que escribe `house_status`, y siempre dentro de la transacción de la visita, la agenda, la venta, la entrega o el cobro.
- no duplicar: nadie recalcula el color al leer.
- tags: vistas 06 39 · ADR-003

### DATO-03 · Cola de sync
- dónde: `core/sync/encolador_sync.dart` (`EncoladorSync`) · `core/sync/sync_providers.dart` (`encoladorSyncProvider`, `motorSyncProvider`) · `lib/datos/encolador_sync_motor.dart` · sync manual: `sincronizadorManualProvider` (`auth/presentation/providers/borrado_providers.dart`)
- uso: `encolar` va **en la misma transacción** que la fila de negocio.
- no duplicar: ninguna llamada directa al servidor para lo que viaja por sync.
- tags: contrato-sync-engine.md · ADR-007 ADR-008

### DATO-04 · RPC directas a Supabase (las únicas en develop)
- dónde: `estado_cuenta` (`auth/data/datasources/estado_cuenta_remote_data_source_supabase.dart`) · `mi_deuda_con_la_casa_editora` (`cuenta/data/datasources/deuda_con_la_casa_remote_data_source.dart`)
- uso: van con `cliente.rpc(...)` dentro de un datasource. Lo demás viaja por `sync_push`/`sync_pull`.
- no duplicar: antes de agregar una RPC nueva, buscá en backend-supabase si ya existe.
- tags: ADR-013

### DATO-05 · Campaña, ciudad, zona y geocodificación
- dónde: `mapa/presentation/providers/alta_ubicacion_providers.dart` (`ciudadesParaAltaProvider`, `ubicadorZonaProvider`, `inscripcionesColportorProvider`, `geocodificadorInversoProvider`, `zonaRepositoryProvider`)
- uso: Precios ya reusa `ciudadesParaAltaProvider.proponer(colportorId:, punto:)`.
- no duplicar: nadie resuelve «en qué ciudad o zona estoy» por su cuenta. Estos providers viven en el archivo del alta aunque los usen otros (moverlos a un `core/` queda a confirmar).
- tags: vistas 03 26 36 · HU-CAT-006 HU-CAM-006

## TEST · Arneses

### TEST-01 · Falsos y arneses compartidos
- dónde: `test/helpers/mapa_base_falso.dart` (`FabricaMapaFalsa`, `VistaMapaFalsa`) · `hoja_casa_falsos.dart` · `alta_ubicacion_falsos.dart` · `zonas_del_mapa_falsos.dart` · `lista_ubicaciones_falsos.dart` · las convenciones en `test/README.md`
- uso: un test de una vista que está sobre el mapa monta `MapaUbicacionesPage` con `FabricaMapaFalsa`.
- no duplicar: ningún falso nuevo del mapa ni de la hoja de la casa.
- tags: vistas 03 05 06 39
