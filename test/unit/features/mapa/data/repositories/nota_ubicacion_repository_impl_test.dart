// Traducción de errores del repositorio de notas de un lugar (vista 39, C·05) y lo que no va al log.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_ubicacion_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/nota_ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_nota.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

final class _Local implements NotaUbicacionLocalDataSource {
  Object? lanza;
  NotaUbicacion? _nota;

  @override
  Future<NotaUbicacion> agregar(NotaUbicacion nota) async => _correr(nota);

  @override
  Future<NotaUbicacion> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) async => _correr(_nota!);

  @override
  Future<NotaUbicacion> borrar({required String id, required DateTime ahora}) async =>
      _correr(_nota!);

  @override
  Future<NotaUbicacion> restaurar({required String id, required DateTime ahora}) async =>
      _correr(_nota!);

  NotaUbicacion _correr(NotaUbicacion nota) {
    _nota = nota;
    final error = lanza;
    if (error != null) throw error;
    return nota;
  }

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) => Stream.value(const []);
}

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  final t0 = DateTime.utc(2026, 10, 22, 12);
  final nota = NotaUbicacion(
    id: 'nota-1',
    ubicacionId: 'ubi-1',
    texto: 'La dueña no quiere visitas',
    auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
  );

  late _Local local;
  late _Salida salida;
  late NotaUbicacionRepositoryImpl repositorio;

  setUp(() {
    local = _Local();
    salida = _Salida();
    repositorio = NotaUbicacionRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.trace, output: salida),
      ),
    );
  });

  test('dado que las operaciones salen bien, devuelven la nota', () async {
    for (final r in [
      await repositorio.agregar(nota),
      await repositorio.editar(id: 'nota-1', texto: 'x', ahora: t0),
      await repositorio.borrar(id: 'nota-1', ahora: t0),
      await repositorio.restaurar(id: 'nota-1', ahora: t0),
    ]) {
      expect(r.getOrElse(() => fail('debía salir bien')), nota);
    }
  });

  test(
    'dado que la persistencia rechaza por un motivo, devuelve un FailureValidacion con su campo',
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
    'dado que la persistencia lanza otra cosa, devuelve FailureInesperado con solo el tipo',
    () async {
      await repositorio.agregar(nota);
      local.lanza = StateError('INSERT INTO nota (texto) VALUES (La dueña no quiere visitas)');

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

  test('dado un rechazo o una falla, el log lleva UUIDs y códigos pero nunca el texto', () async {
    local.lanza = const NotaRechazadaException(MotivoRechazoNota.ubicacionDeBaja);
    await repositorio.agregar(nota);
    local.lanza = StateError('INSERT INTO nota (texto) VALUES (La dueña no quiere visitas)');
    await repositorio.agregar(nota);

    final todo = salida.lineas.join('\n');
    expect(todo, contains('nota-1'));
    expect(todo, contains('NOTA_LUGAR_ALTA_RECHAZADA'));
    expect(todo, contains('NOTA_LUGAR_ALTA_FAIL'));
    expect(todo, isNot(contains('La dueña')));
  });
}
