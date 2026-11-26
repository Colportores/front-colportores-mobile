// «Actualizar ahora» (HU-SYNC-007): la fase que ve la pantalla mientras corre, termina o falla.
import 'dart:async';

import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/providers/sincronizacion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/sincronizacion_falsos.dart';

void main() {
  late ServicioSincronizacionFalso servicio;
  late ProviderContainer c;

  setUp(() {
    servicio = ServicioSincronizacionFalso();
    c = ProviderContainer(overrides: [servicioSincronizacionProvider.overrideWithValue(servicio)]);
    addTearDown(c.dispose);
    c
      ..listen(actualizacionProvider, (_, _) {})
      ..listen(estadoSincronizacionProvider, (_, _) {});
  });

  ActualizacionNotifier notifier() => c.read(actualizacionProvider.notifier);

  test('should start without an update', () {
    expect(c.read(actualizacionProvider), isA<SinActualizar>());
  });

  test('should go through "Actualizando" and end "Actualizado"', () async {
    servicio.actualizacionEnCurso = Completer();
    servicio.emitir(const EstadoSincronizacion(pendientes: 4));
    await Future<void>.delayed(Duration.zero);

    final corriendo = notifier().actualizar();
    expect(c.read(actualizacionProvider), const Actualizando(pendientesAlEmpezar: 4));

    servicio.actualizacionEnCurso!.complete(const ActualizacionCompleta(enviadas: 4));
    await corriendo;

    final fase = c.read(actualizacionProvider);
    expect(fase, isA<Actualizado>());
    expect((fase as Actualizado).resultado.enviadas, 4);
  });

  test('should ignore a second request while one is running', () async {
    servicio.actualizacionEnCurso = Completer();

    final primera = notifier().actualizar();
    await notifier().actualizar();

    expect(servicio.llamadasActualizar, 1);
    servicio.actualizacionEnCurso!.complete(const ActualizacionCompleta());
    await primera;
  });

  test('should number each update so two equal ones are two notices', () async {
    await notifier().actualizar();
    final primera = c.read(actualizacionProvider);
    await notifier().actualizar();
    final segunda = c.read(actualizacionProvider);

    expect(primera, isA<Actualizado>());
    expect(segunda, isA<Actualizado>());
    expect(segunda, isNot(primera));
  });

  test('should end "NoSePudoActualizar" with the reason', () async {
    servicio.resultado = const ActualizacionFallida(MotivoFallaActualizacion.sesion);

    await notifier().actualizar();

    final fase = c.read(actualizacionProvider);
    expect(fase, isA<NoSePudoActualizar>());
    expect((fase as NoSePudoActualizar).motivo, MotivoFallaActualizacion.sesion);
  });

  test('should not stay stuck on "Actualizando" when the engine throws', () async {
    servicio.lanzaAlActualizar = true;

    await notifier().actualizar();

    expect(c.read(actualizacionProvider), isA<NoSePudoActualizar>());
    servicio.lanzaAlActualizar = false;
    await notifier().actualizar();
    expect(c.read(actualizacionProvider), isA<Actualizado>());
  });

  test('should requeue the failed ones before updating', () async {
    await notifier().actualizar(reintentarFallidas: true);
    await notifier().actualizar(idFallida: 'op-9');

    expect(servicio.reintentos, [null, 'op-9']);
    expect(servicio.llamadasActualizar, 2);
  });

  test('should not touch the failed ones on a plain update', () async {
    await notifier().actualizar();

    expect(servicio.reintentos, isEmpty);
  });

  test('should forget an old result but not an update in course', () async {
    await notifier().actualizar();
    notifier().olvidarResultado();
    expect(c.read(actualizacionProvider), isA<SinActualizar>());

    servicio.actualizacionEnCurso = Completer();
    final corriendo = notifier().actualizar();
    notifier().olvidarResultado();
    expect(c.read(actualizacionProvider), isA<Actualizando>());
    servicio.actualizacionEnCurso!.complete(const ActualizacionCompleta());
    await corriendo;
  });

  test('should drop the result of an engine that was replaced meanwhile', () async {
    servicio.actualizacionEnCurso = Completer();
    final conmutable = NotifierProvider<_Conmutador, ServicioSincronizacionFalso>(
      () => _Conmutador(servicio),
    );
    final otro = ServicioSincronizacionFalso();
    final contenedor = ProviderContainer(
      overrides: [servicioSincronizacionProvider.overrideWith((ref) => ref.watch(conmutable))],
    );
    addTearDown(contenedor.dispose);
    contenedor.listen(actualizacionProvider, (_, _) {});

    final corriendo = contenedor.read(actualizacionProvider.notifier).actualizar();
    contenedor.read(conmutable.notifier).poner(otro);
    servicio.actualizacionEnCurso!.complete(const ActualizacionCompleta(enviadas: 9));
    await corriendo;

    expect(contenedor.read(actualizacionProvider), isA<SinActualizar>());
  });
}

class _Conmutador extends Notifier<ServicioSincronizacionFalso> {
  _Conmutador(this._inicial);

  final ServicioSincronizacionFalso _inicial;

  @override
  ServicioSincronizacionFalso build() => _inicial;

  void poner(ServicioSincronizacionFalso nuevo) => state = nuevo;
}
