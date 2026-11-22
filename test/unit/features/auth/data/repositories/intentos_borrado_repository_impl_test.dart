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
  late DateTime ahora;

  /// Una corrida de la app: su reloj monótono arranca donde diga [reloj] (la hora del sistema de
  /// esa corrida no tiene nada que ver con la de la anterior).
  IntentosBorradoRepositoryImpl corrida(DateTime Function() reloj) =>
      IntentosBorradoRepositoryImpl(almacen, reloj, logger: loggerMudo());

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    ahora = DateTime.utc(2026, 9, 30, 12);
    repo = corrida(() => ahora);
  });

  test('sin nada guardado, el estado está limpio', () async {
    expect(await repo.leer(), EstadoIntentosBorrado.limpio);
  });

  test(
    'guarda y lee los intentos y el fin de la espera (como lo haría otra sesión de la app)',
    () async {
      final fin = ahora.add(const Duration(minutes: 5));
      await repo.guardar(EstadoIntentosBorrado(fallidos: 2));
      expect((await repo.leer()).fallidos, 2);

      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));
      // Un repositorio nuevo sobre el mismo almacén = la app cerrada y vuelta a abrir.
      final reabierto = corrida(() => ahora);
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
      final reabierto = corrida(() => ahora);

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

  group('la espera no depende de la hora del sistema entre corridas', () {
    final fin = DateTime.utc(2026, 9, 30, 12, 5);

    test('se guarda lo que falta, no una hora', () async {
      await repo.guardar(EstadoIntentosBorrado(fallidos: 5, bloqueadoHasta: fin));

      expect(almacen.contenido[ClaveSegura.intentosBorrado], '5|300000');
    });

    test('lo que falta se achica con la corrida y se guarda de nuevo', () async {
      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));
      ahora = ahora.add(const Duration(minutes: 2));

      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));

      expect(almacen.contenido[ClaveSegura.intentosBorrado], '0|180000');
    });

    test('adelantar la hora del sistema y reabrir la app no saltea la espera', () async {
      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));

      // Otra corrida, con la hora del sistema un día adelantada.
      final manana = ahora.add(const Duration(days: 1));
      final estado = await corrida(() => manana).leer();

      expect(estado.bloqueadoEn(manana), isTrue);
      expect(estado.bloqueadoHasta, manana.add(const Duration(minutes: 5)));
    });

    test('atrasar la hora del sistema tampoco la alarga', () async {
      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));

      final ayer = ahora.subtract(const Duration(days: 1));
      final estado = await corrida(() => ayer).leer();

      expect(estado.bloqueadoHasta, ayer.add(const Duration(minutes: 5)));
    });

    test('dentro de una corrida, leer dos veces da la misma espera', () async {
      await repo.guardar(EstadoIntentosBorrado(bloqueadoHasta: fin));
      var reloj = ahora.add(const Duration(days: 1));
      final reabierto = corrida(() => reloj);

      final primera = await reabierto.leer();
      reloj = reloj.add(const Duration(minutes: 1));
      final segunda = await reabierto.leer();

      expect(segunda.bloqueadoHasta, primera.bloqueadoHasta);
    });

    test('con los intentos pero sin espera, no hay espera al reabrir', () async {
      await repo.guardar(EstadoIntentosBorrado(fallidos: 3));

      final estado = await corrida(() => ahora).leer();

      expect(estado.fallidos, 3);
      expect(estado.bloqueadoHasta, isNull);
    });

    test('un valor guardado con la hora (formato anterior) vuelve a esperar completo', () async {
      await almacen.escribir(ClaveSegura.intentosBorrado, '5|${fin.toIso8601String()}');

      final estado = await corrida(() => ahora).leer();

      expect(estado.ilegible, isFalse);
      expect(estado.bloqueadoHasta, ahora.add(const Duration(minutes: 5)));
    });

    test('una espera negativa guardada es un valor mal formado: falla cerrado', () async {
      await almacen.escribir(ClaveSegura.intentosBorrado, '5|-1000');

      expect((await corrida(() => ahora).leer()).ilegible, isTrue);
    });
  });
}
