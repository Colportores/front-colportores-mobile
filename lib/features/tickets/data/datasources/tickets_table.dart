import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `ticket` de la DB local cifrada (esquema-datos.md §ticket, HU-COB-007).
///
/// Es la misma tabla que `public.ticket` del cloud (`backend-supabase`, migraciones 0067, 0113, 0134 y
/// 0146), con las diferencias de motor de [Cobranzas]: fechas en epoch ms UTC, sin claves foráneas y
/// sin defaults de servidor. El dinero va en **centavos** (`int`), nunca `double`.
///
/// Sube por el motor (`push`, con `alsoPull` de lo propio). Las columnas que escribe **solo el
/// servidor** están acá porque bajan con el pull (para ver el estado del ticket sin conexión,
/// HU-COB-009): `usuario_id`, `subido_en`, `estado`, `revisado_por`, `revisado_en`, `motivo_rechazo`
/// y `campania_validadora_id`. El push las descarta y el modelo no las manda.
///
/// **La foto no viaja por el motor.** `url_cloud` guarda la ruta del objeto en el bucket
/// (`<usuario_id>/<ticket_id>.<ext>`) y se completa una sola vez, cuando la foto sube. Lo que es solo
/// del teléfono (la copia local, el estado de la subida) vive en [TicketFotosLocales], porque una
/// entidad que sube no lleva columnas que no suben (contrato §2).
///
/// Los CHECK repiten los del servidor, pero **`monto` y `fecha` aceptan `NULL`**: un ticket de antes
/// de la migración 0113 los puede tener vacíos y un CHECK local no puede frenar un delta válido. El
/// caso de uso nunca arma un ticket sin ellos.
///
/// **Sin dato del cliente** (ADR-004): la foto y la fila no llevan nombre, teléfono ni dirección.
@DataClassName('TicketFila')
class Tickets extends Table {
  @override
  String get tableName => 'ticket';

  TextColumn get id => text()();

  /// La dueña. La pone el servidor (`auth.uid()`); en un ticket recién creado en el teléfono está vacía
  /// hasta que el pull trae la fila.
  TextColumn get usuarioId => text().nullable()();

  /// `COBRO_TARJETA`, `DEPOSITO` u `OTRO`.
  TextColumn get tipo => text()();

  /// La ruta de la foto en el bucket; vacía hasta que la foto sube (y de nuevo vacía a los 4 meses).
  TextColumn get urlCloud => text().nullable()();

  /// Cuándo llegó al servidor, con su reloj.
  IntColumn get subidoEn => integer().nullable().map(const FechaUtcConverter())();

  TextColumn get revisadoPor => text().nullable()();

  IntColumn get revisadoEn => integer().nullable().map(const FechaUtcConverter())();

  /// Lo que dice el ticket, en centavos; mayor que cero.
  IntColumn get monto => integer().nullable()();

  /// La fecha del ticket.
  IntColumn get fecha => integer().nullable().map(const FechaUtcConverter())();

  /// El número de autorización (1 a 40 caracteres); en el de un depósito, el número de operación.
  TextColumn get numeroAutorizacion => text().nullable()();

  /// `CREDITO` o `DEBITO`.
  TextColumn get tarjetaTipo => text().nullable()();

  TextColumn get tarjetaMarca => text().nullable()();

  /// `PENDIENTE`, `VALIDADO` o `RECHAZADO`. Lo cambia el coordinador.
  TextColumn get estado => text().withDefault(const Constant('PENDIENTE'))();

  TextColumn get motivoRechazo => text().nullable()();

  /// La campaña cuya coordinadora lo valida; vacía = lo revisa Administración (backend 0146).
  TextColumn get campaniaValidadoraId => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  IntColumn get updatedAt => integer().map(const FechaUtcConverter())();

  TextColumn get createdBy => text().nullable()();

  /// Soft delete (esquema-datos.md §Principios 6). Desde el teléfono no se da de baja un ticket.
  IntColumn get deletedAt => integer().nullable().map(const FechaUtcConverter())();

  IntColumn get syncVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (tipo IN ('COBRO_TARJETA', 'DEPOSITO', 'OTRO'))",
    "CHECK (estado IN ('PENDIENTE', 'VALIDADO', 'RECHAZADO'))",
    'CHECK (monto IS NULL OR monto > 0)',
    "CHECK (tarjeta_tipo IS NULL OR tarjeta_tipo IN ('CREDITO', 'DEBITO'))",
  ];
}

/// Tabla `ticket_foto_local`: la copia comprimida de la foto de un ticket y cómo va su subida
/// (HU-COB-007, supuesto S41). **Solo del teléfono** (política `local`): no sube por el motor, la foto
/// va por el enlace firmado de `foto-ticket`.
///
/// Una fila por ticket (su clave es `ticket_id`). `ruta_local` queda vacía cuando el colportor borra la
/// copia. El archivo está en el directorio privado de la app, no en la galería.
@DataClassName('TicketFotoLocalFila')
class TicketFotosLocales extends Table {
  @override
  String get tableName => 'ticket_foto_local';

  TextColumn get ticketId => text()();

  /// `image/jpeg`, `image/png` o `image/webp`: lo que firma el enlace de subida.
  TextColumn get tipoDeImagen => text()();

  /// El tamaño del archivo, en bytes (lo que firma el enlace de subida); mayor que cero.
  IntColumn get bytes => integer()();

  /// `PENDIENTE`, `SUBIDA` o `RECHAZADA`.
  TextColumn get estado => text().withDefault(const Constant('PENDIENTE'))();

  /// Dónde está el archivo en el teléfono; vacía si el colportor borró la copia.
  TextColumn get rutaLocal => text().nullable()();

  /// Cuántas veces se intentó subir.
  IntColumn get intentos => integer().withDefault(const Constant(0))();

  /// El código del último error de la subida (`red`, `foto_ya_subida`…); nunca texto del servidor.
  TextColumn get ultimoError => text().nullable()();

  IntColumn get creadaEn => integer().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {ticketId};

  @override
  List<String> get customConstraints => const [
    'CHECK (bytes > 0)',
    "CHECK (estado IN ('PENDIENTE', 'SUBIDA', 'RECHAZADA'))",
    'CHECK (intentos >= 0)',
  ];
}
