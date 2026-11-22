// HU-UBI-001: lo que hace el alta mientras no existen las inscripciones ni el motor de sync. Ninguno
// inventa datos. (Las ciudades de la campaña ya salen de las réplicas locales: `ciudades_para_alta_local_test.dart`.)
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja.dart'
    show TextosBaja;
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  test('la falla de lectura dice qué pasa y qué hacer, con el texto del aviso de la vista 03', () {
    const falla = FailureCiudadesNoDisponibles();

    expect(falla.mensaje, TextosAlta.ciudadesNoLeidas);
    expect(falla.mensaje, contains('Probá de nuevo'));
    expect(falla.mensaje, isNot(contains('coordinador')), reason: 'no manda a molestar a nadie');
  });

  test('el aviso de que falta la ciudad de la campaña guía al colportor', () {
    expect(const FailureCiudadRequerida().mensaje, contains('Elegí una de las ciudades'));
  });

  test(
    'sin inscripciones: lista vacía, el alta queda sin zona local y el servidor la calcula',
    () async {
      final r = await InscripcionesColportorSinFuente().vigentesDe('col-1');

      expect(r.getOrElse(() => throw StateError('falló')), isEmpty);
    },
  );

  test(
    'sin visitas, ventas ni cobranzas en el teléfono: la revisión de la baja falla (no afirma que no '
    'hay nada) y deja el aviso PENDIENTES_SIN_FUENTE',
    () async {
      final salida = _SalidaEnMemoria();
      final c = PendientesUbicacionSinFuente(logger: AppLogger(output: salida));

      expect(
        await c.de('ubi-1'),
        const Left<Failure, PendientesUbicacion>(FailurePendientesNoDisponibles()),
      );

      expect(
        salida.lineas.where((l) => l.startsWith('[WARN][MAP][PENDIENTES_SIN_FUENTE]')),
        hasLength(1),
      );
    },
  );

  test('la falla de revisión dice qué pasa y qué hacer, con el texto de la hoja de baja', () {
    const falla = FailurePendientesNoDisponibles();

    expect(falla.mensaje, TextosBaja.noPudimosRevisar);
    expect(falla.mensaje, contains('Probá de nuevo'));
    expect(falla.codigo, 'UBI_PENDIENTES_NO_DISPONIBLES');
  });

  test('sin motor de sync encolar falla: un alta que no sube no se guarda', () async {
    await expectLater(
      const EncoladorSyncSinMotor().encolar('ubicacion', OperacionSync.insert, const {}),
      throwsStateError,
    );
  });

  test('sin la base local abierta no hay repositorio de ubicaciones ni de zonas', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(() => c.read(ubicacionRepositoryProvider), throwsA(isA<ProviderException>()));
    expect(() => c.read(zonaRepositoryProvider), throwsA(isA<ProviderException>()));
  });

  test('sin la base abierta, el contexto del mapa no tiene ubicaciones', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    const consulta = (
      colportorId: 'col-1',
      area: AreaMapa(sur: -35, oeste: -57, norte: -34, este: -56),
    );
    c.listen(marcadoresCercanosProvider(consulta), (_, _) {});
    final lista = await c.read(marcadoresCercanosProvider(consulta).future);

    expect(lista, isEmpty);
  });
}
