// Traducción de errores del repositorio de notas de una persona (HU-UBI-012) y lo que no va al log.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/nota_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

final class _Local implements NotaPersonaLocalDataSource {
  Object? lanza;
  ContextoNotasPersona? contexto;

  NotaPersona? _nota;

  @override
  Future<NotaPersona> agregar(NotaPersona nota) async => _correr(nota);

  @override
  Future<NotaPersona> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) async => _correr(_nota!);

  @override
  Future<NotaPersona> borrar({required String id, required DateTime ahora}) async =>
      _correr(_nota!);

  @override
  Future<NotaPersona> restaurar({required String id, required DateTime ahora}) async =>
      _correr(_nota!);

  NotaPersona _correr(NotaPersona nota) {
    _nota = nota;
    final error = lanza;
    if (error != null) throw error;
    return nota;
  }

  @override
  Stream<List<NotaPersona>> observar(String personaId) => Stream.value(const []);

  @override
  Future<ContextoNotasPersona?> leerContexto(String personaId) async {
    final error = lanza;
    if (error != null) throw error;
    return contexto;
  }
}

/// Un `LogOutput` que junta todo lo que se imprimió.
final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 12);
  final nota = NotaPersona(
    id: 'nota-1',
    personaId: 'per-1',
    texto: 'Le debe plata a la hermana',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  late _Local local;
  late _Salida salida;
  late NotaPersonaRepositoryImpl repositorio;

  setUp(() {
    local = _Local();
    salida = _Salida();
    repositorio = NotaPersonaRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.trace, output: salida),
      ),
    );
  });

  test('dado que agregar sale bien, cuando agrego, devuelve la nota', () async {
    final r = await repositorio.agregar(nota);

    expect(r.getOrElse(() => fail('debía salir bien')), nota);
  });

  test(
    'dado que editar, borrar y restaurar salen bien, cuando los llamo, devuelven la nota',
    () async {
      await repositorio.agregar(nota);

      for (final r in [
        await repositorio.editar(id: 'nota-1', texto: 'x', ahora: t0),
        await repositorio.borrar(id: 'nota-1', ahora: t0),
        await repositorio.restaurar(id: 'nota-1', ahora: t0),
      ]) {
        expect(r.isRight(), isTrue);
      }
    },
  );

  test(
    'dado que la persistencia rechaza por un motivo, cuando agrego, devuelve un FailureValidacion con su campo y su mensaje',
    () async {
      for (final motivo in MotivoRechazoNota.values) {
        local.lanza = NotaRechazadaException(motivo);

        final r = await repositorio.agregar(nota);

        final falla = r.fold((f) => f, (_) => fail('debía fallar'));
        expect(falla, isA<FailureValidacion>());
        expect((falla as FailureValidacion).campos, {motivo.campo: motivo.mensaje});
      }
    },
  );

  test(
    'dado que la persistencia lanza otra cosa, cuando opero, devuelve FailureInesperado con solo el tipo de la causa',
    () async {
      await repositorio.agregar(nota);
      local.lanza = StateError('INSERT INTO nota (texto) VALUES (Le debe plata a la hermana)');

      for (final r in [
        await repositorio.agregar(nota),
        await repositorio.editar(id: 'nota-1', texto: 'x', ahora: t0),
        await repositorio.borrar(id: 'nota-1', ahora: t0),
        await repositorio.restaurar(id: 'nota-1', ahora: t0),
      ]) {
        final falla = r.fold((f) => f, (_) => fail('debía fallar'));
        expect(falla, isA<FailureInesperado>());
        expect((falla as FailureInesperado).causa, 'StateError');
      }
    },
  );

  test(
    'dado un rechazo o una falla, cuando opero, el log lleva UUIDs y códigos pero nunca el texto de la nota',
    () async {
      local.lanza = const NotaRechazadaException(MotivoRechazoNota.soloLectura);
      await repositorio.agregar(nota);
      local.lanza = StateError('INSERT INTO nota (texto) VALUES (Le debe plata a la hermana)');
      await repositorio.agregar(nota);

      final todo = salida.lineas.join('\n');
      expect(todo, contains('nota-1'));
      expect(todo, contains('NOTA_ALTA_RECHAZADA'));
      expect(todo, contains('NOTA_ALTA_FAIL'));
      expect(todo, isNot(contains('Le debe plata')));
    },
  );

  test(
    'dado una persona, cuando leo el contexto, devuelve el nombre y si es de solo lectura',
    () async {
      local.contexto = const ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.personaDeBaja,
      );

      final r = await repositorio.leerContexto('per-1');

      expect(
        r.getOrElse(() => null),
        const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.personaDeBaja),
      );
    },
  );

  test('dado que leer el contexto lanza, cuando lo leo, devuelve FailureInesperado', () async {
    local.lanza = StateError('boom');

    final r = await repositorio.leerContexto('per-1');

    expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
  });

  test('dado un contexto, cuando se lo imprime, no muestra el nombre de la persona', () {
    expect(const ContextoNotasPersona(nombre: 'María').toString(), isNot(contains('María')));
  });

  test('dado una nota, cuando se la imprime, no muestra su texto', () {
    expect(nota.toString(), isNot(contains('Le debe plata')));
  });
}
