import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/espacio_persona.dart';
import '../../domain/entities/motivo_rechazo_persona.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/entities/persona.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/services/contador_personas_espacio.dart';
import '../models/espacio_persona_model.dart';
import 'espacio_personas_table.dart';
import 'espacios_table.dart';
import 'notas_table.dart';
import 'persona_local_data_source.dart';
import 'personas_table.dart';
import 'ubicaciones_table.dart';

part 'persona_local_data_source_drift.g.dart';

typedef _Motivo = MotivoRechazoPersona;

/// [PersonaLocalDataSource] sobre las tablas `persona` ([Personas]), `espacio_persona`
/// ([EspacioPersonas]) y `nota` ([Notas]) de la DB cifrada. También es el adaptador de producción de
/// [ContadorPersonasEspacio] (la baja de espacios, HU-UBI-007).
///
/// Es un DAO (`@DriftAccessor`), como `UbicacionLocalDataSourceDrift`. El sync entra por
/// [EncoladorSync], dentro de la misma transacción que la escritura (contrato-sync-engine §3), y
/// **solo** para el vínculo: la persona y la nota son `local` (Ley 18.331) y no se encolan.
@DriftAccessor(tables: [Personas, EspacioPersonas, Notas, Espacios, Ubicaciones])
final class PersonaLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$PersonaLocalDataSourceDriftMixin
    implements PersonaLocalDataSource, ContadorPersonasEspacio {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10).
  PersonaLocalDataSourceDrift(super.attachedDatabase, {required this._encolador});

  final EncoladorSync _encolador;

  /// Buscar, decidir y escribir van en una sola transacción: Drift no corre dos a la vez sobre la
  /// misma DB, así que dos altas casi simultáneas (un doble toque) se serializan y la segunda ya ve
  /// la primera —la misma persona (mismo `id`)—.
  @override
  Future<RegistroPersona> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) => transaction(() async {
    final existente = await (select(
      personas,
    )..where((p) => p.id.equals(persona.id))).getSingleOrNull();
    if (existente != null) return (persona: _aPersona(existente), yaEstaba: true);

    await _exigirEspacioActivo(vinculo.espacioId);
    await into(personas).insert(_aFilaPersona(persona));
    await into(espacioPersonas).insert(_aFilaVinculo(vinculo));
    await _encolador.encolar(
      'espacio_persona',
      OperacionSync.insert,
      EspacioPersonaModel.fromEntity(vinculo).toJson(),
    );
    if (nota != null) await into(notas).insert(_aFilaNota(nota));
    return (persona: persona, yaEstaba: false);
  });

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) {
    final consulta =
        select(
            espacioPersonas,
          ).join([innerJoin(personas, personas.id.equalsExp(espacioPersonas.personaId))])
          ..where(
            espacioPersonas.espacioId.equals(espacioId) &
                espacioPersonas.deletedAt.isNull() &
                personas.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.asc(personas.createdAt), OrderingTerm.asc(personas.id)]);
    return consulta.watch().map(
      (filas) => [
        for (final fila in filas)
          PersonaDelEspacio(
            persona: _aPersona(fila.readTable(personas)),
            vinculo: _aVinculo(fila.readTable(espacioPersonas)),
          ),
      ],
    );
  }

  @override
  Future<int> activasEn(String espacioId) async {
    final cantidad = personas.id.count();
    final consulta =
        selectOnly(
            espacioPersonas,
          ).join([innerJoin(personas, personas.id.equalsExp(espacioPersonas.personaId))])
          ..addColumns([cantidad])
          ..where(
            espacioPersonas.espacioId.equals(espacioId) &
                espacioPersonas.deletedAt.isNull() &
                personas.deletedAt.isNull(),
          );
    return (await consulta.getSingle()).read(cantidad) ?? 0;
  }

  /// El espacio tiene que existir y no estar dado de baja, y su ubicación tampoco. Si la ubicación no
  /// está en el teléfono (el pull no garantiza el orden) no se bloquea: ante una fila que falta no se
  /// inventa un motivo para frenar el alta.
  Future<void> _exigirEspacioActivo(String espacioId) async {
    final espacio = await (select(
      espacios,
    )..where((e) => e.id.equals(espacioId))).getSingleOrNull();
    if (espacio == null) throw const PersonaRechazadaException(_Motivo.espacioInexistente);
    if (espacio.deletedAt != null) throw const PersonaRechazadaException(_Motivo.espacioDeBaja);

    final ubicacion = await (select(
      ubicaciones,
    )..where((u) => u.id.equals(espacio.ubicacionId))).getSingleOrNull();
    if (ubicacion != null && ubicacion.deletedAt != null) {
      throw const PersonaRechazadaException(_Motivo.ubicacionDeBaja);
    }
  }

  static Persona _aPersona(PersonaFila fila) => Persona(
    id: fila.id,
    nombre: fila.nombre,
    apellido: fila.apellido,
    telefono: fila.telefono,
    notasGlobales: fila.notasGlobales,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static EspacioPersona _aVinculo(EspacioPersonaFila fila) => EspacioPersona(
    id: fila.id,
    espacioId: fila.espacioId,
    personaId: fila.personaId,
    ubicacionCobranzaAltId: fila.ubicacionCobranzaAltId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static PersonasCompanion _aFilaPersona(Persona p) => PersonasCompanion.insert(
    id: p.id,
    nombre: p.nombre,
    apellido: Value(p.apellido),
    telefono: Value(p.telefono),
    notasGlobales: Value(p.notasGlobales),
    createdAt: p.auditoria.createdAt,
    updatedAt: p.auditoria.updatedAt,
    createdBy: Value(p.auditoria.createdBy),
    deletedAt: Value(p.auditoria.deletedAt),
    syncVersion: Value(p.auditoria.syncVersion),
  );

  static EspacioPersonasCompanion _aFilaVinculo(EspacioPersona v) =>
      EspacioPersonasCompanion.insert(
        id: v.id,
        espacioId: v.espacioId,
        personaId: v.personaId,
        ubicacionCobranzaAltId: Value(v.ubicacionCobranzaAltId),
        createdAt: v.auditoria.createdAt,
        updatedAt: v.auditoria.updatedAt,
        createdBy: Value(v.auditoria.createdBy),
        deletedAt: Value(v.auditoria.deletedAt),
        syncVersion: Value(v.auditoria.syncVersion),
      );

  static NotasCompanion _aFilaNota(NotaPersona n) => NotasCompanion.insert(
    id: n.id,
    targetType: TipoObjetivoNota.persona,
    targetId: n.personaId,
    texto: n.texto,
    createdAt: n.auditoria.createdAt,
    updatedAt: n.auditoria.updatedAt,
    createdBy: Value(n.auditoria.createdBy),
    deletedAt: Value(n.auditoria.deletedAt),
    syncVersion: Value(n.auditoria.syncVersion),
  );
}
