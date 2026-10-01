// Los intentos de contraseña del borrado (vista 19) se guardan en el almacén seguro: cerrar la app
// no reinicia la espera.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/intentos_borrado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_intentos_borrado.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late IntentosBorradoRepositoryImpl repo;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    repo = IntentosBorradoRepositoryImpl(almacen, logger: loggerMudo());
  });

  test('sin nada guardado, el estado está limpio', () async {
    expect(await repo.leer(), EstadoIntentosBorrado.limpio);
  });

  test(
    'guarda y lee los intentos y el fin de la espera (como lo haría otra sesión de la app)',
    () async {
      final fin = DateTime.utc(2026, 9, 30, 12, 5);
      await repo.guardar(EstadoIntentosBorrado(fallidos: 2));
      expect((await repo.leer()).fallidos, 2);

      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));
      // Un repositorio nuevo sobre el mismo almacén = la app cerrada y vuelta a abrir.
      final reabierto = IntentosBorradoRepositoryImpl(almacen, logger: loggerMudo());
      expect((await reabierto.leer()).bloqueadoHasta, fin);
    },
  );

  test('limpiar borra lo guardado', () async {
    await repo.guardar(EstadoIntentosBorrado(fallidos: 3));

    await repo.limpiar();

    expect(almacen.contenido, isNot(contains(ClaveSegura.intentosBorrado)));
    expect(await repo.leer(), EstadoIntentosBorrado.limpio);
  });

  test('un valor mal formado no resetea los intentos: falla cerrado (ilegible)', () async {
    for (final basura in ['basura', 'x|', '-1|', '1|no-es-fecha']) {
      await almacen.escribir(ClaveSegura.intentosBorrado, basura);
      final reabierto = IntentosBorradoRepositoryImpl(almacen, logger: loggerMudo());

      final estado = await reabierto.leer();

      expect(estado.ilegible, isTrue, reason: basura);
      expect(estado, isNot(EstadoIntentosBorrado.limpio));
    }
  });

  test('si el almacén no se lee, falla cerrado (ilegible) y no lanza', () async {
    almacen.simularFalla = true;

    expect((await repo.leer()).ilegible, isTrue);
    await expectLater(repo.limpiar(), completes);
  });

  test('si el almacén no deja escribir, el intento igual cuenta en esta corrida', () async {
    almacen.simularFalla = true;

    await expectLater(repo.guardar(EstadoIntentosBorrado(fallidos: 2)), completes);

    final estado = await repo.leer();
    expect(estado.ilegible, isFalse);
    expect(estado.fallidos, 2);
  });

  test('limpiar con el almacén roto igual deja el contador limpio en esta corrida', () async {
    await repo.guardar(EstadoIntentosBorrado(fallidos: 3));
    almacen.simularFalla = true;

    await repo.limpiar();

    expect(await repo.leer(), EstadoIntentosBorrado.limpio);
  });
}
