// La fuente de las inscripciones con zona (HU-CAM-006, #251): la versión en memoria simula los pulls
// (la de las réplicas locales se prueba en `inscripciones_con_zona_local_test.dart`).
import 'package:colportores_mobile/features/auth/data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:flutter_test/flutter_test.dart';

const _centro = InscripcionConZona(
  id: 'insc-1',
  campaniaId: 'camp-1',
  campaniaNombre: 'Primavera',
  zonaId: 'z-centro',
  zonaNombre: 'Centro',
);

void main() {
  group('InscripcionesConZonaEnMemoria', () {
    test('al suscribirse emite lo que hay; después, cada pull', () async {
      final fuente = InscripcionesConZonaEnMemoria();
      final emisiones = <List<InscripcionConZona>>[];
      final suscripcion = fuente.observar('u-1').listen(emisiones.add);
      await pumpEventQueue();

      fuente.publicar([_centro]);
      fuente.publicar(const []);
      await pumpEventQueue();

      expect(emisiones, [
        isEmpty,
        [_centro],
        isEmpty,
      ]);
      expect(fuente.suscripciones, 1);
      await suscripcion.cancel();
    });

    test('una suscripción nueva arranca con lo último publicado', () async {
      final fuente = InscripcionesConZonaEnMemoria([_centro]);

      expect(await fuente.observar('u-1').first, [_centro]);
    });

    test('dos suscriptores reciben el mismo pull y uno cancelado deja de recibir', () async {
      final fuente = InscripcionesConZonaEnMemoria();
      final a = <List<InscripcionConZona>>[];
      final b = <List<InscripcionConZona>>[];
      final subA = fuente.observar('u-1').listen(a.add);
      final subB = fuente.observar('u-1').listen(b.add);
      await pumpEventQueue();
      await subB.cancel();

      fuente.publicar([_centro]);
      await pumpEventQueue();

      expect(a.last, [_centro]);
      expect(b, [isEmpty]);
      await subA.cancel();
    });

    test(
      'con falla, emite el error en lugar de las inscripciones; fallar() lo emite en medio',
      () async {
        final fuente = InscripcionesConZonaEnMemoria()..falla = StateError('rota');
        final errores = <Object>[];
        final suscripcion = fuente.observar('u-1').listen((_) {}, onError: errores.add);
        await pumpEventQueue();

        fuente.fallar(StateError('otra'));
        await pumpEventQueue();

        expect(errores, hasLength(2));
        await suscripcion.cancel();
      },
    );
  });
}
