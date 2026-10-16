// El motivo y la fecha del último cierre que la persona no pidió viven en el almacén seguro, junto
// al correo y nada más, y las operaciones salen en el orden en que se piden (decisión de Cristian,
// 07/10, #302).
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/cierre_forzado.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacén donde escribir tarda, para probar el orden.
final class _AlmacenLento implements AlmacenSeguro {
  final AlmacenSeguroEnMemoria _real = AlmacenSeguroEnMemoria();

  @override
  Future<String?> leer(ClaveSegura clave) => _real.leer(clave);

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _real.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) => _real.borrar(clave);

  @override
  Future<void> borrarTodo() => _real.borrarTodo();
}

void main() {
  final fecha = DateTime.utc(2026, 10, 7, 8, 2, 30);
  final inactividad = CierreForzado(motivo: MotivoExpiracion.inactividad, fecha: fecha);
  final revocada = CierreForzado(motivo: MotivoExpiracion.revocada, fecha: fecha);

  late AlmacenSeguroEnMemoria almacen;
  late CierreForzadoRepositoryImpl repo;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = CierreForzadoRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, no hay cierre', () async {
    expect(await repo.leer(), isNull);
  });

  test('guarda solo el motivo y la fecha, con la clave propia, y lo lee una app que se abre de '
      'nuevo', () async {
    await repo.guardar(inactividad);

    expect(almacen.contenido, {ClaveSegura.cierreForzado: 'inactividad|2026-10-07T08:02:30.000Z'});
    final reabierto = CierreForzadoRepositoryImpl(almacen, logger: loggerMudo());
    expect(await reabierto.leer(), inactividad);
  });

  test('cada motivo se lee como se guardó', () async {
    for (final cierre in [inactividad, revocada]) {
      await repo.guardar(cierre);

      expect((await repo.leer())!.motivo, cierre.motivo);
    }
  });

  test('la fecha vuelve en UTC y con los microsegundos que tenía', () async {
    final conMicros = CierreForzado(
      motivo: MotivoExpiracion.revocada,
      fecha: DateTime.utc(2026, 10, 7, 8, 2, 30, 123, 456),
    );
    await repo.guardar(conMicros);

    final leido = (await repo.leer())!;

    expect(leido.fecha.isUtc, isTrue);
    expect(leido.fecha, conMicros.fecha);
  });

  test('guardar otro cierre reemplaza al anterior', () async {
    await repo.guardar(inactividad);
    await repo.guardar(revocada);

    expect(await repo.leer(), revocada);
  });

  test('borrar lo olvida, y borrar sin nada guardado no falla', () async {
    await repo.guardar(inactividad);
    await repo.borrar();
    expect(await repo.leer(), isNull);
    expect(almacen.contenido, isEmpty);

    await expectLater(repo.borrar(), completes);
  });

  test('no toca el correo de la última cuenta que está al lado', () async {
    await almacen.escribir(ClaveSegura.ultimoCorreo, 'ana@example.com');

    await repo.guardar(inactividad);
    await repo.borrar();

    expect(almacen.contenido, {ClaveSegura.ultimoCorreo: 'ana@example.com'});
  });

  group('un valor guardado que no se puede leer es «no hay cierre» (no se inventa un aviso)', () {
    for (final (nombre, valor) in const [
      ('en blanco', '  '),
      ('sin fecha', 'inactividad'),
      ('con un motivo que no existe', 'cerrada|2026-10-07T08:02:30.000Z'),
      ('con la fecha rota', 'revocada|ayer'),
      ('con partes de más', 'revocada|2026-10-07T08:02:30.000Z|otra'),
      ('con la fecha vacía', 'revocada|'),
    ]) {
      test(nombre, () async {
        await almacen.escribir(ClaveSegura.cierreForzado, valor);

        expect(await repo.leer(), isNull);
      });
    }

    test('y un cierre nuevo lo reemplaza', () async {
      await almacen.escribir(ClaveSegura.cierreForzado, 'basura');

      await repo.guardar(revocada);

      expect(await repo.leer(), revocada);
    });
  });

  test('guardar y borrar sin esperar: gana el borrado, aunque el guardado tarde', () async {
    final lento = _AlmacenLento();
    final repoLento = CierreForzadoRepositoryImpl(lento, logger: loggerMudo());

    final guardado = repoLento.guardar(inactividad);
    final borrado = repoLento.borrar();
    await Future.wait([guardado, borrado]);

    expect(await repoLento.leer(), isNull);
  });

  test('borrar y guardar sin esperar: queda el último guardado', () async {
    await repo.guardar(inactividad);

    final borrado = repo.borrar();
    final guardado = repo.guardar(revocada);
    await Future.wait([borrado, guardado]);

    expect(await repo.leer(), revocada);
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('leer devuelve null en vez de lanzar', () async {
      expect(await repo.leer(), isNull);
    });

    test('guardar y borrar no lanzan (solo van al log)', () async {
      await expectLater(repo.guardar(inactividad), completes);
      await expectLater(repo.borrar(), completes);
    });

    test('una falla no traba las operaciones siguientes', () async {
      await repo.guardar(inactividad);
      almacen.simularFalla = false;

      await repo.guardar(revocada);

      expect(await repo.leer(), revocada);
    });
  });

  test('CierreForzado guarda la fecha siempre en UTC', () {
    final local = DateTime(2026, 10, 7, 8, 2, 30);

    final cierre = CierreForzado(motivo: MotivoExpiracion.inactividad, fecha: local);

    expect(cierre.fecha.isUtc, isTrue);
    expect(cierre.fecha, local.toUtc());
    expect(
      cierre,
      CierreForzado(motivo: MotivoExpiracion.inactividad, fecha: local.toUtc()),
      reason: 'el mismo instante, local o UTC, es el mismo cierre',
    );
  });

  test('CierreForzadoEnMemoria guarda, reemplaza y borra', () async {
    final memoria = CierreForzadoEnMemoria();
    expect(await memoria.leer(), isNull);

    await memoria.guardar(inactividad);
    expect(await memoria.leer(), inactividad);

    await memoria.guardar(revocada);
    expect(await memoria.leer(), revocada);

    await memoria.borrar();
    expect(await memoria.leer(), isNull);
  });
}
