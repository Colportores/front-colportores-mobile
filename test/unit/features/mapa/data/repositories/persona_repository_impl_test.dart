// Traducción de errores del repositorio de personas (HU-UBI-008) y su payload de sync.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_persona_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _Local implements PersonaLocalDataSource {
  Object? lanza;

  @override
  Future<RegistroPersona> registrar({
    required Persona persona,
    required EspacioPersona vinculo,
    NotaPersona? nota,
  }) async {
    final error = lanza;
    if (error != null) throw error;
    return (persona: persona, yaEstaba: false);
  }

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => const Stream.empty();

  @override
  Stream<List<PersonaDelEspacio>> observarBajasDelEspacio(String espacioId) => const Stream.empty();

  @override
  Future<Persona> darDeBaja({
    required String personaId,
    required DateTime ahora,
    String? motivo,
  }) async {
    final error = lanza;
    if (error != null) throw error;
    return baja!;
  }

  @override
  Future<Persona> reactivar({required String personaId, required DateTime ahora}) async {
    final error = lanza;
    if (error != null) throw error;
    return baja!;
  }

  /// Lo que devuelven [darDeBaja] y [reactivar].
  Persona? baja;
}

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 12);
  final auditoria = Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1');
  final persona = Persona(
    id: 'per-1',
    nombre: 'Ana',
    apellido: 'Martínez',
    telefono: '099 123 456',
    auditoria: auditoria,
  );
  final vinculo = EspacioPersona(
    id: 'ep-1',
    espacioId: 'esp-1',
    personaId: 'per-1',
    auditoria: auditoria,
  );

  late _Local local;
  late PersonaRepositoryImpl repositorio;

  setUp(() {
    local = _Local();
    repositorio = PersonaRepositoryImpl(local, logger: loggerMudo());
  });

  test('dado que el alta sale bien, cuando registra, devuelve la persona', () async {
    final r = await repositorio.registrar(persona: persona, vinculo: vinculo);

    expect(r.getOrElse(() => throw StateError('falló')), persona);
  });

  test('dado un espacio dado de baja, cuando registra, devuelve una validación con el mensaje '
      'de la baja', () async {
    local.lanza = const PersonaRechazadaException(MotivoRechazoPersona.espacioDeBaja);

    final r = await repositorio.registrar(persona: persona, vinculo: vinculo);

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureValidacion>());
    expect(
      (falla! as FailureValidacion).campos['espacio'],
      MotivoRechazoPersona.espacioDeBaja.mensaje,
    );
  });

  test(
    'dado un error inesperado con datos personales, cuando registra, la falla no los lleva',
    () async {
      local.lanza = StateError('INSERT INTO persona (nombre) VALUES (Ana Martínez 099 123 456)');

      final r = await repositorio.registrar(persona: persona, vinculo: vinculo);

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureInesperado>());
      expect('${falla!.props}', isNot(contains('Martínez')));
      expect('${falla.props}', isNot(contains('099')));
    },
  );

  group('baja y reactivación (HU-UBI-011)', () {
    test('dada una baja que sale bien, devuelve la persona', () async {
      local.baja = persona;

      final r = await repositorio.darDeBaja(personaId: 'per-1', ahora: t0, motivo: 'Se mudó');

      expect(r.getOrElse(() => throw StateError('falló')), persona);
    });

    test(
      'dada una persona de solo lectura, la baja devuelve una validación con el mensaje',
      () async {
        local.lanza = const PersonaRechazadaException(MotivoRechazoPersona.personaSoloLectura);

        final r = await repositorio.darDeBaja(personaId: 'per-1', ahora: t0);

        final falla = r.fold((f) => f, (_) => null)! as FailureValidacion;
        expect(falla.campos['persona'], MotivoRechazoPersona.personaSoloLectura.mensaje);
      },
    );

    test('dada una persona que ya no está, reactivar devuelve una validación', () async {
      local.lanza = const PersonaRechazadaException(MotivoRechazoPersona.personaInexistente);

      final r = await repositorio.reactivar(personaId: 'per-1', ahora: t0);

      final falla = r.fold((f) => f, (_) => null)! as FailureValidacion;
      expect(falla.campos['persona'], MotivoRechazoPersona.personaInexistente.mensaje);
    });

    test('dado un error inesperado con datos personales, la falla no los lleva', () async {
      local.lanza = StateError('UPDATE persona SET nombre = Ana Martínez 099 123 456');

      final baja = await repositorio.darDeBaja(personaId: 'per-1', ahora: t0, motivo: 'Secreto');
      final reactivacion = await repositorio.reactivar(personaId: 'per-1', ahora: t0);

      for (final r in [baja, reactivacion]) {
        final falla = r.fold((f) => f, (_) => null);
        expect(falla, isA<FailureInesperado>());
        expect('${falla!.props}', isNot(contains('Martínez')));
        expect('${falla.props}', isNot(contains('Secreto')));
      }
    });
  });

  test('dado un vínculo, cuando se arma el payload de sync, lleva solo ids y auditoría', () {
    final json = EspacioPersonaModel.fromEntity(vinculo).toJson();

    expect(json.keys, {
      'id',
      'espacio_id',
      'persona_id',
      'ubicacion_cobranza_alt_id',
      'created_at',
      'updated_at',
      'created_by',
      'deleted_at',
      'sync_version',
    });
    expect(json['persona_id'], 'per-1');
    expect(json['espacio_id'], 'esp-1');
  });
}
