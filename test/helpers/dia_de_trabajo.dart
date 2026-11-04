// Un día de trabajo del colportor, hecho con el código real de la app (los DAOs escriben en la DB Drift
// y encolan por el motor) y con los ids que genera el teléfono de verdad: UUID v7. Los tests del motor
// usan ids de mentira (`ub-1`, `jor-1`) porque el servidor falso los acepta; el real los rechaza
// (`(payload ->> pk)::uuid`).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:sync_engine/sync_engine.dart';

/// El colportor de la demo (el mismo que arma el script de la base del otro lado).
const colportorDemo = '01920000-0000-7000-8000-00000000c001';

/// La ciudad donde trabaja.
const ciudadDemo = '01920000-0000-7000-8000-00000000c002';

/// Los pasos del día, en el orden en que el colportor los hace. Cada paso escribe en la DB local y
/// encola por el motor, dentro de la misma transacción, como en el teléfono.
final class DiaDeTrabajo {
  DiaDeTrabajo(
    AppDatabase db,
    SyncEngine motor, {
    required this._inicio,
    this.calle = 'Rivera',
    this.numero = '1234',
    this.lat = -34.9,
    this.lon = -56.16,
  }) : _jornadas = JornadaLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
       _ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
       _personas = PersonaLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
       _agenda = AgendaLocalDataSourceDrift(
         db,
         encolador: EncoladorSyncMotor(motor),
         estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: EncoladorSyncMotor(motor)),
       );

  final DateTime _inicio;

  /// Dónde queda la casa. El servidor no deja dos casas a menos de 100 m con la misma dirección
  /// (`ubicacion_direccion_unica`): contra una base compartida, cada día pide la suya.
  final String calle;
  final String numero;
  final double lat;
  final double lon;
  final JornadaLocalDataSourceDrift _jornadas;
  final UbicacionLocalDataSourceDrift _ubicaciones;
  final PersonaLocalDataSourceDrift _personas;
  final AgendaLocalDataSourceDrift _agenda;
  final _uuid = UuidV7();

  late final String jornadaId = _uuid.next();
  late final String ubicacionId = _uuid.next();
  late final String espacioId = _uuid.next();
  late final String personaId = _uuid.next();
  late final String vinculoId = _uuid.next();
  late final String agendaId = _uuid.next();
  late final String visitaId = _uuid.next();

  JornadaModel? _jornada;
  UbicacionModel? _ubicacion;

  /// Un instante del día, [minutos] después de empezar.
  DateTime en(int minutos) => _inicio.add(Duration(minutes: minutos));

  Auditoria _aud(DateTime t) => Auditoria(createdAt: t, updatedAt: t, createdBy: colportorDemo);

  /// El día entero, de la jornada que abre a la jornada que cierra.
  Future<void> correrTodo() async {
    await empezarJornada();
    await altaDeLaCasa();
    await altaDeLaPersona();
    await agendar();
    await registrarLaVisita();
    await cerrarJornada();
  }

  Future<void> empezarJornada() async {
    final t = en(0);
    _jornada = JornadaModel.fromJson({
      'id': jornadaId,
      'colportor_id': colportorDemo,
      'inicio': t.toIso8601String(),
      'fin': null,
      'acompaniante_id': null,
      'tipo_acompaniamiento': null,
      'total_visitas': 0,
      'total_ventas': 0,
      'created_at': t.toIso8601String(),
      'updated_at': t.toIso8601String(),
      'created_by': colportorDemo,
      'deleted_at': null,
      'sync_version': 0,
    });
    await _jornadas.insertar(_jornada!);
  }

  Future<void> altaDeLaCasa() async {
    final t = en(20);
    _ubicacion = UbicacionModel.fromJson({
      'id': ubicacionId,
      'tipo': 'CASA',
      'calle': calle,
      'numero': numero,
      'lat': lat,
      'lon': lon,
      'ciudad_id': ciudadDemo,
      'zona_id': null,
      'created_at': t.toIso8601String(),
      'updated_at': t.toIso8601String(),
      'created_by': colportorDemo,
      'deleted_at': null,
      'sync_version': 0,
    });
    await _ubicaciones.insertar(
      _ubicacion!,
      espacio: EspacioModel.fromJson({
        'id': espacioId,
        'ubicacion_id': ubicacionId,
        'numero_depto': null,
        'piso': null,
        'created_at': t.toIso8601String(),
        'updated_at': t.toIso8601String(),
        'created_by': colportorDemo,
        'deleted_at': null,
        'sync_version': 0,
      }),
    );
  }

  Future<void> altaDeLaPersona() async {
    final t = en(25);
    await _personas.registrar(
      persona: Persona(
        id: personaId,
        nombre: 'Ana',
        apellido: 'Pérez',
        telefono: '099123456',
        auditoria: _aud(t),
      ),
      vinculo: EspacioPersona(
        id: vinculoId,
        espacioId: espacioId,
        personaId: personaId,
        auditoria: _aud(t),
      ),
    );
  }

  /// Una entrevista para dentro de dos días, con una nota que no sube.
  Future<void> agendar() async {
    final t = en(30);
    await _agenda.agendar(
      Agenda(
        id: agendaId,
        espacioId: espacioId,
        espacioPersonaId: vinculoId,
        tipo: TipoAgenda.entrevista,
        fechaProgramada: _inicio.add(const Duration(days: 2)),
        colportorId: colportorDemo,
        auditoria: _aud(t),
      ),
      nota: NotaDeCampo(id: _uuid.next(), texto: 'Atiende de tarde', auditoria: _aud(t)),
    );
  }

  /// La visita que cumple esa agenda.
  Future<void> registrarLaVisita() async {
    final t = en(45);
    await _agenda.registrarVisita(
      Visita(
        id: visitaId,
        espacioId: espacioId,
        espacioPersonaId: vinculoId,
        fecha: t,
        tipoResultado: TipoResultadoVisita.entrevista,
        colportorId: colportorDemo,
        jornadaId: jornadaId,
        auditoria: _aud(t),
      ),
      agendaId: agendaId,
    );
  }

  Future<void> cerrarJornada() async {
    final fin = en(8 * 60);
    _jornada = JornadaModel.fromJson({
      ..._jornada!.toJson(),
      'fin': fin.toIso8601String(),
      'updated_at': fin.toIso8601String(),
    });
    await _jornadas.finalizar(_jornada!);
  }

  /// Una corrección sobre una casa que ya subió: la calle estaba mal escrita.
  Future<void> corregirLaCalle(String calle, {required int minuto}) async {
    final actual = (await _ubicaciones.obtener(ubicacionId))!;
    final t = en(minuto);
    _ubicacion = await _ubicaciones.actualizar(
      UbicacionModel.fromJson({
        ...actual.toJson(),
        'calle': calle,
        'updated_at': t.toIso8601String(),
      }),
      baseUpdatedAt: actual.auditoria.updatedAt,
    );
  }

  /// Otra visita en la misma casa, sin cita previa («No contestó»): cambia el color de la casa.
  Future<String> visitaSinCita({required int minuto}) async {
    final id = _uuid.next();
    final t = en(minuto);
    await _agenda.registrarVisita(
      Visita(
        id: id,
        espacioId: espacioId,
        espacioPersonaId: vinculoId,
        fecha: t,
        tipoResultado: TipoResultadoVisita.noContesto,
        colportorId: colportorDemo,
        jornadaId: jornadaId,
        auditoria: _aud(t),
      ),
    );
    return id;
  }

  /// Cancela una agenda.
  Future<void> cancelar(String agendaId, {required int minuto}) async {
    await _agenda.cancelar(agendaId, ahora: en(minuto));
  }

  /// Una agenda nueva para [dias] días, sobre la misma casa.
  Future<String> agendarOtra({required int dias, required int minuto}) async {
    final id = _uuid.next();
    await _agenda.agendar(
      Agenda(
        id: id,
        espacioId: espacioId,
        espacioPersonaId: vinculoId,
        tipo: TipoAgenda.entrevista,
        fechaProgramada: _inicio.add(Duration(days: dias)),
        colportorId: colportorDemo,
        auditoria: _aud(en(minuto)),
      ),
    );
    return id;
  }
}
