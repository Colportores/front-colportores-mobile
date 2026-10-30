import 'package:drift/drift.dart';

import '../../datos/sync_queue_table.dart';
import '../../features/agenda/data/datasources/agendas_table.dart';
import '../../features/agenda/data/datasources/visitas_table.dart';
import '../../features/auth/data/datasources/sesion_usuario_table.dart';
import '../../features/catalogo/data/datasources/colecciones_table.dart';
import '../../features/catalogo/data/datasources/parametros_globales_table.dart';
import '../../features/catalogo/data/datasources/precios_generales_table.dart';
import '../../features/catalogo/data/datasources/precios_por_ciudad_table.dart';
import '../../features/catalogo/data/datasources/producto_colecciones_table.dart';
import '../../features/catalogo/data/datasources/productos_table.dart';
import '../../features/cobranzas/data/datasources/cobranzas_table.dart';
import '../../features/depositos/data/datasources/depositos_table.dart';
import '../../features/jornada/data/datasources/jornadas_table.dart';
import '../../features/mapa/data/datasources/audit_log_table.dart';
import '../../features/mapa/data/datasources/campanias_ciudad_table.dart';
import '../../features/mapa/data/datasources/campanias_colportor_table.dart';
import '../../features/mapa/data/datasources/campanias_table.dart';
import '../../features/mapa/data/datasources/ciudades_table.dart';
import '../../features/mapa/data/datasources/espacio_personas_table.dart';
import '../../features/mapa/data/datasources/espacios_table.dart';
import '../../features/mapa/data/datasources/geojson_converter.dart';
import '../../features/mapa/data/datasources/house_status_table.dart';
import '../../features/mapa/data/datasources/notas_table.dart';
import '../../features/mapa/data/datasources/pares_duplicados_table.dart';
import '../../features/mapa/data/datasources/personas_table.dart';
import '../../features/mapa/data/datasources/ubicaciones_table.dart';
import '../../features/mapa/data/datasources/zona_vertices_table.dart';
import '../../features/mapa/data/datasources/zonas_table.dart';
import '../../features/notificaciones/data/datasources/notificacion_historial_table.dart';
import '../../features/stock/data/datasources/stocks_table.dart';
import '../../features/ventas/data/datasources/componentes_converter.dart';
import '../../features/ventas/data/datasources/devoluciones_table.dart';
import '../../features/ventas/data/datasources/entregas_table.dart';
import '../../features/ventas/data/datasources/productos_devueltos_converter.dart';
import '../../features/ventas/data/datasources/venta_items_table.dart';
import '../../features/ventas/data/datasources/ventas_table.dart';
import '../logging/app_logger.dart';
import 'app_database.steps.dart';
import 'fecha_utc_converter.dart';

part 'app_database.g.dart';

/// Base de datos local de la app: Drift sobre SQLite cifrado con SQLCipher (ADR-006, ADR-009).
///
/// Es la clase que consume el resto de la app —y el motor de sync de ADR-017 (`SyncEngine(db:
/// appDb)`, `appDb.transaction(...)`)—. **No sabe de cifrado**: recibe una conexión ya abierta con
/// la clave puesta; eso lo hace `DatabaseHelper`, que es el único que conoce el `PRAGMA key`.
///
/// Las tablas de negocio llegan con cada HU (convenciones §4.2) y viven en su feature
/// (`features/<feature>/data/datasources/<tabla>_table.dart`); acá solo se registran en
/// `@DriftDatabase(tables: [...])`. `drift_dev` genera `_$AppDatabase` en `app_database.g.dart`,
/// que no se versiona: lo regenera `build_runner`, también en CI. Agregar una tabla es siempre lo
/// mismo: sumarla a la lista, subir [versionEsquema] y escribir su paso en [migration], con test.
///
/// Las fechas de toda tabla van en epoch ms UTC con [FechaUtcConverter]
/// (08-conceptos-transversales §8.11), no con columnas `dateTime()` de Drift.
@DriftDatabase(
  tables: [
    Jornadas,
    Ubicaciones,
    Espacios,
    ParesDecididos,
    CampaniasCiudad,
    Zonas,
    ZonaVertices,
    SesionUsuarios,
    AuditLogLocal,
    SyncQueue,
    SyncWatermarks,
    SyncMetas,
    Personas,
    EspacioPersonas,
    Notas,
    Agendas,
    Visitas,
    HouseStatuses,
    NotificacionesHistorial,
    Productos,
    Colecciones,
    ProductoColecciones,
    PreciosPorCiudad,
    PreciosGenerales,
    ParametrosGlobales,
    Stocks,
    Ciudades,
    Campanias,
    CampaniasColportor,
    Ventas,
    VentaItems,
    Cobranzas,
    Entregas,
    Devoluciones,
    Depositos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  /// Versión del esquema (`PRAGMA user_version`). Constante además de getter porque
  /// `DatabaseHelper` la necesita **antes** de construir la DB: el `setup` de la conexión rechaza
  /// un archivo de una versión posterior antes de que Drift lo migre.
  ///
  /// Historia (forward-only, 08-conceptos-transversales §8.10):
  /// - 1: sin tablas (#6).
  /// - 2: `jornada` (#70).
  /// - 3: `ubicacion` y `espacio` (#192).
  /// - 4: `ubicacion_par_decidido`, solo local (#207).
  /// - 5: `campania_ciudad`, `zona` y `zona_vertice`, réplicas del canal de catálogo (#231).
  /// - 6: `sesion_usuario`, copia local del nombre del usuario (#243).
  /// - 7: `audit_log`, la auditoría del dispositivo, solo local (#205: el motivo de la baja).
  /// - 8: `sync_queue` y `sync_watermark`, la cola y los watermarks del motor de sync (#178).
  /// - 9: `persona` y `nota`, solo locales, y `espacio_persona`, que sube solo con ids (HU-UBI-008, #140).
  /// - 10: `agenda` y `visita`, que suben, y la cache `house_status`, que también (BACK-HU-VIS-001, #404).
  /// - 11: `agenda` y `visita` cuelgan del espacio (`espacio_id`), la persona es opcional, la agenda
  ///   usa los estados de la HU (`PROGRAMADA`, `CUMPLIDA`, `NO_CUMPLIDA`, `CANCELADA`) y la visita
  ///   suma el resultado `COBRANZA` (backend 0068 y 0069, #411).
  /// - 12: `notificacion_historial`, el historial del centro de notificaciones, solo local
  ///   (HU-NOT-005, #156).
  /// - 13: `sync_meta`, lo que el motor se acuerda entre aperturas: última bajada, último respaldo y
  ///   la red del último envío (HU-SYNC-007, #486).
  /// - 14: las réplicas del catálogo de ventas, `producto`, `coleccion`, `producto_coleccion`,
  ///   `precio_por_ciudad` y `precio_general` (HU-SYNC-002, HU-SYNC-003, HU-CAT-007, #180).
  /// - 15: `stock`, la réplica de solo lectura del inventario del colportor (HU-STK-004, #545).
  /// - 16: las réplicas de `ciudad`, `campania` y `campania_colportor` (las inscripciones propias):
  ///   de dónde salen las ciudades de la campaña del colportor sin red (#274).
  /// - 17: `venta` y `venta_item`, las ventas del colportor (HU-VEN-001, #423).
  /// - 18: `producto.codigo_editor` (el código de la casa editora, opcional) y `parametro_global`, la
  ///   réplica de solo lectura de los parámetros de toda la aplicación, hoy los días del aviso de
  ///   precios viejos (backend-supabase 0070, HU-CAT-006, #419).
  /// - 19: `cobranza`, el cobro en efectivo, que sube (HU-COB-001, #436).
  /// - 20: `cobranza` suma los datos opcionales de la tarjeta (`tarjeta_tipo`, `tarjeta_marca`,
  ///   `numero_aprobacion`) y de la transferencia (`referencia_transferencia`, `banco_origen`), que
  ///   suben con el cobro (backend-supabase 0072, HU-COB-002 y HU-COB-003, #396).
  /// - 21: `entrega`, lo entregado de cada venta, una fila por producto, que sube (HU-VEN-002, #430).
  /// - 22: `devolucion`, las devoluciones de una venta (qué libros vuelven y qué se hace con la plata de
  ///   más), que sube (HU-VEN-004, #161; backend-supabase 0108, 0136 y 0142).
  /// - 23: `deposito`, el efectivo que el colportor depositó, con su destino, su concepto y su ticket,
  ///   que sube (HU-CTA-004, #442).
  ///
  /// Al subirla: `dart run drift_dev make-migrations` congela la versión nueva en `drift_schemas/`,
  /// regenera `app_database.steps.dart` y los tests de `test/drift/` (convenciones §9).
  static const int versionEsquema = 23;

  /// Versión del esquema (`PRAGMA user_version`). HU-AUTH-009 la lee para validar que la DB abrió
  /// bien; `DatabaseHelper.abrir` hace esa comprobación.
  @override
  int get schemaVersion => versionEsquema;

  /// Una DB nueva se crea entera con el esquema actual ([Migrator.createAll]). Una existente sube
  /// paso a paso desde su versión con [stepByStep] (`app_database.steps.dart`, generado por
  /// `drift_dev make-migrations`): cada paso `fromNToM` recibe el esquema **congelado** de la
  /// versión `M` (`drift_schemas/`), así que crear una tabla en el paso 1 → 2 la crea como era en
  /// la 2 aunque después cambie. Un paso ya publicado no se edita. Los tests de
  /// `test/drift/app_database/` migran desde cada versión congelada y comparan con
  /// `SchemaVerifier` (convenciones §9).
  ///
  /// **Toda la subida va en una transacción, con `user_version` adentro.** Drift 2.34 corre
  /// `onUpgrade` sin transacción y escribe la versión recién al final, y `createIndex` no usa
  /// `IF NOT EXISTS`: un corte a mitad de camino (disco lleno, la app matada) dejaría las tablas
  /// del paso a medias con la versión vieja, y cada apertura siguiente fallaría en el mismo
  /// `CREATE INDEX` —la DB quedaría inabrible y solo quedaría "Empezar de nuevo", con las jornadas
  /// sin sincronizar adentro—. En SQLite el DDL es transaccional: si algo falla se revierte todo y
  /// la próxima apertura reintenta desde la versión de antes.
  ///
  /// `beforeOpen` agrega el log `[DB][MIGRATION]` de convenciones §7.4.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, desde, hasta) => transaction(() async {
      await _pasos(m, desde, hasta);
      await customStatement('PRAGMA user_version = $hasta');
    }),
    beforeOpen: (detalles) async {
      if (detalles.wasCreated) {
        _log.info(LogModulo.db, 'DB_CREADA', 'esquema inicial creado', {'version': schemaVersion});
      } else if (detalles.hadUpgrade) {
        _log.info(LogModulo.db, 'MIGRATION', 'migración ejecutada', {
          'from': detalles.versionBefore,
          'to': detalles.versionNow,
        });
      }
    },
  );

  /// Los pasos `N → N+1` contra el esquema congelado de cada versión (`app_database.steps.dart`).
  static final OnUpgrade _pasos = stepByStep(
    from1To2: (m, esquema) async {
      await m.createTable(esquema.jornada);
      await m.createIndex(esquema.jornadaColportorIdx);
    },
    from2To3: (m, esquema) async {
      await m.createTable(esquema.ubicacion);
      await m.createIndex(esquema.ubicacionCiudadIdx);
      await m.createTable(esquema.espacio);
      await m.createIndex(esquema.espacioUbicacionIdx);
    },
    // Solo crea una tabla: las jornadas, ubicaciones y espacios quedan como estaban.
    from3To4: (m, esquema) async {
      await m.createTable(esquema.ubicacionParDecidido);
    },
    // Solo crea las réplicas del catálogo, vacías (las llena el pull): las jornadas, ubicaciones,
    // espacios y pares decididos quedan como estaban.
    from4To5: (m, esquema) async {
      await m.createTable(esquema.campaniaCiudad);
      await m.createIndex(esquema.campaniaCiudadCiudadIdIdx);
      await m.createTable(esquema.zona);
      await m.createIndex(esquema.zonaCampaniaCiudadIdx);
      await m.createTable(esquema.zonaVertice);
      await m.createIndex(esquema.zonaVerticeZonaIdx);
    },
    // Solo crea la tabla del nombre, vacía (se llena al entrar): nada de lo guardado cambia.
    from5To6: (m, esquema) async {
      await m.createTable(esquema.sesionUsuario);
    },
    // Solo crea la auditoría local, vacía: nada de lo guardado cambia (las bajas anteriores quedan
    // sin motivo y la Lista no muestra ninguno).
    from6To7: (m, esquema) async {
      await m.createTable(esquema.auditLog);
      await m.createIndex(esquema.auditLogEventoUuidIdx);
    },
    // Solo crea la cola y los watermarks del motor, vacíos: nada de lo guardado cambia. Lo que se
    // dio de alta antes de la 8 no se encoló nunca (sin motor, encolar fallaba y el alta no se
    // guardaba), así que no hay nada que recuperar.
    from7To8: (m, esquema) async {
      await m.createTable(esquema.syncQueue);
      await m.createIndex(esquema.syncQueueEstadoOrden);
      await m.createIndex(esquema.syncQueueFila);
      await m.createIndex(esquema.syncQueueDoneAt);
      await m.createTable(esquema.syncWatermark);
    },
    // Solo crea las tablas de las personas, vacías: nada de lo guardado cambia.
    from8To9: (m, esquema) async {
      await m.createTable(esquema.persona);
      await m.createTable(esquema.espacioPersona);
      await m.createIndex(esquema.espacioPersonaEspacioIdx);
      await m.createIndex(esquema.espacioPersonaPersonaIdx);
      await m.createTable(esquema.nota);
      await m.createIndex(esquema.notaObjetivoIdx);
    },
    // Solo crea las tablas de la agenda, las visitas y la cache del color de las casas, vacías: nada
    // de lo guardado cambia ni se encola al migrar.
    from9To10: (m, esquema) async {
      await m.createTable(esquema.agenda);
      await m.createIndex(esquema.agendaColportorIdx);
      await m.createIndex(esquema.agendaEspacioPersonaIdx);
      await m.createTable(esquema.visita);
      await m.createIndex(esquema.visitaColportorIdx);
      await m.createIndex(esquema.visitaEspacioPersonaIdx);
      await m.createTable(esquema.houseStatus);
    },
    // Reescribe `visita` y `agenda` (SQLite no cambia un NOT NULL ni un CHECK): conserva todas las
    // filas. El `espacio_id` sale del vínculo que ya tenían (`espacio_persona.espacio_id`); un
    // vínculo que todavía no llegó al teléfono deja el espacio vacío (no se inventa uno). Los
    // estados viejos de la agenda pasan a los de la HU. Nada se encola al migrar.
    from10To11: (m, esquema) async {
      const espacioDelVinculo = CustomExpression<String>(
        'COALESCE((SELECT ep.espacio_id FROM espacio_persona ep '
        "WHERE ep.id = espacio_persona_id), '')",
      );
      await m.alterTable(
        TableMigration(
          esquema.visita,
          newColumns: [esquema.visita.espacioId],
          columnTransformer: {esquema.visita.espacioId: espacioDelVinculo},
        ),
      );
      await m.alterTable(
        TableMigration(
          esquema.agenda,
          newColumns: [esquema.agenda.espacioId],
          columnTransformer: {
            esquema.agenda.espacioId: espacioDelVinculo,
            esquema.agenda.estado: const CustomExpression<String>(
              "CASE estado WHEN 'PENDIENTE' THEN 'PROGRAMADA' "
              "WHEN 'COMPLETADA' THEN 'CUMPLIDA' ELSE estado END",
            ),
          },
        ),
      );
      // `alterTable` vuelve a crear los índices que ya tenía cada tabla, no los nuevos.
      await m.createIndex(esquema.visitaEspacioIdx);
      await m.createIndex(esquema.agendaEspacioIdx);
    },
    // Solo crea el historial de avisos, vacío: nada de lo guardado cambia.
    from11To12: (m, esquema) async {
      await m.createTable(esquema.notificacionHistorial);
      await m.createIndex(esquema.notificacionHistorialRecibidaIdx);
    },
    // Solo crea la tabla de metadatos del motor, vacía: nada de lo guardado cambia. Hasta que el
    // motor anote algo, la vista de estado dice «Todavía no hubo».
    from12To13: (m, esquema) async {
      await m.createTable(esquema.syncMeta);
    },
    // Solo crea las réplicas del catálogo de ventas, vacías (las llena el pull, entero la primera
    // vez): nada de lo guardado cambia. El servidor baja desde cero toda entidad que el watermark
    // del teléfono no tiene, así que no hace falta tocar `sync_watermark`.
    from13To14: (m, esquema) async {
      await m.createTable(esquema.producto);
      await m.createTable(esquema.coleccion);
      await m.createTable(esquema.productoColeccion);
      await m.createIndex(esquema.productoColeccionColeccionIdx);
      await m.createTable(esquema.precioPorCiudad);
      await m.createIndex(esquema.precioPorCiudadCampaniaCiudadIdx);
      await m.createIndex(esquema.precioPorCiudadProductoIdx);
      await m.createIndex(esquema.precioPorCiudadColeccionIdx);
      await m.createTable(esquema.precioGeneral);
      await m.createIndex(esquema.precioGeneralProductoIdx);
      await m.createIndex(esquema.precioGeneralColeccionIdx);
    },
    // Solo crea la réplica del stock, vacía (la llena el pull, entero la primera vez): nada de lo
    // guardado cambia ni se encola al migrar.
    from14To15: (m, esquema) async {
      await m.createTable(esquema.stock);
      await m.createIndex(esquema.stockUsuarioIdx);
    },
    // Solo crea las réplicas de las ciudades y de las campañas del colportor, vacías (las llena el
    // pull, entero la primera vez): nada de lo guardado cambia. Borra la fecha de la última bajada
    // de `sync_meta`: una instalación que viene de la versión anterior ya bajó alguna vez, pero estas
    // réplicas todavía no, y «hubo una bajada y no hay inscripciones» no es «no hay campañas» sino
    // «todavía no sé» (`CampaniasDelColportorLocalDataSourceDrift.leer`). El watermark de cada
    // entidad no se toca: el servidor baja desde cero las que el teléfono nunca bajó.
    from15To16: (m, esquema) async {
      await m.createTable(esquema.ciudad);
      await m.createTable(esquema.campania);
      await m.createTable(esquema.campaniaColportor);
      await m.createIndex(esquema.campaniaColportorUsuarioIdx);
      await m.database.customStatement("DELETE FROM sync_meta WHERE clave = 'last_pull_at'");
    },
    // Solo crea las ventas y sus ítems, vacíos: nada de lo guardado cambia ni se encola al migrar.
    from16To17: (m, esquema) async {
      await m.createTable(esquema.venta);
      await m.createIndex(esquema.ventaColportorIdx);
      await m.createIndex(esquema.ventaEspacioPersonaIdx);
      await m.createTable(esquema.ventaItem);
      await m.createIndex(esquema.ventaItemVentaIdx);
    },
    // Suma la columna `codigo_editor` a `producto` (vacía: ninguna fila que ya estaba cambia) y crea
    // `parametro_global`, vacía (la llena el pull, entero la primera vez: el servidor baja desde cero
    // toda entidad que el watermark del teléfono no tiene). Sin código, el producto se encuentra por
    // nombre, que es lo que pasaba hasta ahora. Un producto ya bajado recibe su código cuando
    // Administración lo cambia en el servidor (agregar la columna no mueve el cursor del delta).
    from17To18: (m, esquema) async {
      await m.addColumn(esquema.producto, esquema.producto.codigoEditor);
      await m.createTable(esquema.parametroGlobal);
    },
    // Solo crea los cobros, vacía: nada de lo guardado cambia ni se encola al migrar.
    from18To19: (m, esquema) async {
      await m.createTable(esquema.cobranza);
      await m.createIndex(esquema.cobranzaVentaIdx);
    },
    // Suma a `cobranza` los datos opcionales de la tarjeta y de la transferencia, vacíos: ningún cobro
    // que ya estaba cambia ni se vuelve a encolar al migrar.
    from19To20: (m, esquema) async {
      await m.addColumn(esquema.cobranza, esquema.cobranza.tarjetaTipo);
      await m.addColumn(esquema.cobranza, esquema.cobranza.tarjetaMarca);
      await m.addColumn(esquema.cobranza, esquema.cobranza.numeroAprobacion);
      await m.addColumn(esquema.cobranza, esquema.cobranza.referenciaTransferencia);
      await m.addColumn(esquema.cobranza, esquema.cobranza.bancoOrigen);
    },
    // Solo crea la tabla de las entregas, vacía: nada de lo guardado cambia ni se encola al migrar.
    // Las ventas de antes quedan sin entrega registrada (los datos son simulados hasta diciembre).
    from20To21: (m, esquema) async {
      await m.createTable(esquema.entrega);
      await m.createIndex(esquema.entregaVentaIdx);
    },
    // Solo crea la tabla de las devoluciones, vacía: nada de lo guardado cambia ni se encola al migrar.
    from21To22: (m, esquema) async {
      await m.createTable(esquema.devolucion);
      await m.createIndex(esquema.devolucionVentaIdx);
    },
    // Solo crea la tabla de los depósitos, vacía: nada de lo guardado cambia ni se encola al migrar.
    from22To23: (m, esquema) async {
      await m.createTable(esquema.deposito);
      await m.createIndex(esquema.depositoTicketIdx);
    },
  );
}
