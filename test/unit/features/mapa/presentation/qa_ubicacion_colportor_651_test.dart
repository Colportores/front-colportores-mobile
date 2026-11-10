// QA #651 (PR #660): casos límite del GPS único que no cubren los tests del implementador.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart'
    show EstadoGpsLista;
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/lista_ubicaciones_falsos.dart';

Left<Failure, T> _sin<T>(MotivoSinGps motivo) => Left(FailureGpsNoDisponible(motivo: motivo));

ProviderContainer _contenedor(GpsFalso gps) {
  final c = ProviderContainer(
    overrides: overridesLista(repo: RepoListaFalso(), gps: gps),
  );
  addTearDown(c.dispose);
  c.listen(ubicacionColportorProvider, (_, _) {});
  return c;
}

void main() {
  test('dado permiso denegado, cuando una vista pide «Volver a mi ubicación» (refrescar), entonces '
      'consulta al sistema otra vez: es la única vía, además de «Activar GPS», que puede mostrar el '
      'diálogo fuera del mapa (pregunta de QA #651: Modificar)', () async {
    final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado));
    final c = _contenedor(gps);
    await c.read(ubicacionColportorProvider.notifier).alAbrirPestana();

    final salida = await c.read(ubicacionColportorProvider.notifier).refrescar();

    expect(salida.isLeft(), isTrue);
    expect(gps.lecturas, 2);
    expect(c.read(ubicacionColportorProvider).gps, EstadoGpsLista.sinGps);
  });

  test(
    'dado «Activar GPS» con una lectura en vuelo, cuando llegan las dos fuera de orden, entonces '
    'queda la posición de la última pedida y nada queda «buscando»',
    () async {
      final primera = Completer<void>();
      final segunda = Completer<void>();
      final gps = GpsFalso(_sin(MotivoSinGps.permisoDenegado))
        ..porLectura = (n) async {
          if (n == 1) return _sin(MotivoSinGps.permisoDenegado);
          await (n == 2 ? primera : segunda).future;
          return Right(lecturaGps(n == 2 ? 50 : 4));
        };
      final c = _contenedor(gps);
      final u = c.read(ubicacionColportorProvider.notifier);
      await u.alAbrirPestana();

      final activar = u.activarGps();
      await pumpEventQueue();
      unawaited(u.refrescar());
      await pumpEventQueue();
      segunda.complete();
      await pumpEventQueue();
      primera.complete();
      await activar;
      await pumpEventQueue();

      final estado = c.read(ubicacionColportorProvider);
      expect(estado.gps, EstadoGpsLista.conLectura);
      expect(estado.lectura!.precisionMetros, 4);
    },
  );

  test('«Activar GPS» tocado de nuevo después de terminar la primera vez vuelve a funcionar (el '
      'guardia de doble toque no queda trabado si la lectura falla)', () async {
    final gps = GpsFalso(_sin(MotivoSinGps.servicioApagado))
      ..alActivar = () => throw StateError('x');
    final c = _contenedor(gps);
    final u = c.read(ubicacionColportorProvider.notifier);
    await u.alAbrirPestana();

    await u.activarGps();
    await u.activarGps();

    expect(gps.activaciones, hasLength(2));
    expect(c.read(ubicacionColportorProvider).gps, EstadoGpsLista.sinGps);
  });

  test('el estado y la lectura no vuelcan coordenadas en toString() (privacidad §7.5)', () async {
    final c = _contenedor(GpsFalso());
    await c.read(ubicacionColportorProvider.notifier).alAbrirPestana();
    final estado = c.read(ubicacionColportorProvider);

    expect(estado.lectura, isNotNull);
    expect(estado.toString(), isNot(contains('-34.887')));
    expect(estado.lectura.toString(), isNot(contains('-56.130')));
  });
}
