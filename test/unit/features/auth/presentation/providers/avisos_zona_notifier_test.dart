// Los avisos de zona pendientes (HU-CAM-006, #251): se arman con lo que el pull deja en el teléfono,
// se quedan hasta que la persona los cierra y se anotan como avisados recién entonces.
import 'dart:async';

import 'package:colportores_mobile/features/auth/data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/aviso_zona.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/zonas_avisadas_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _usuario = 'u-1';

InscripcionConZona _inscripcion({
  String id = 'insc-1',
  String? zonaId,
  String? zonaNombre,
  bool dadaDeBaja = false,
}) => InscripcionConZona(
  id: id,
  campaniaId: 'camp-1',
  campaniaNombre: 'Primavera',
  zonaId: zonaId,
  zonaNombre: zonaNombre,
  dadaDeBaja: dadaDeBaja,
);

final _centro = _inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro');
final _norte = _inscripcion(zonaId: 'z-norte', zonaNombre: 'Norte');
const _asignadaCentro = ZonaAsignada(
  inscripcionId: 'insc-1',
  campaniaNombre: 'Primavera',
  zonaId: 'z-centro',
  zonaNombre: 'Centro',
);
const _asignadaNorte = ZonaAsignada(
  inscripcionId: 'insc-1',
  campaniaNombre: 'Primavera',
  zonaId: 'z-norte',
  zonaNombre: 'Norte',
);
const _quitada = ZonaQuitada(inscripcionId: 'insc-1', campaniaNombre: 'Primavera');

/// Repositorio donde anotar espera a que el test lo libere.
final class _RepositorioLento implements ZonasAvisadasRepository {
  final _real = ZonasAvisadasEnMemoria();
  Completer<void>? compuertaAnotar;
  int anotaciones = 0;

  @override
  Future<Map<String, String?>> leer() => _real.leer();

  @override
  Future<void> anotar(Map<String, String?> avisadas) async {
    // Como el repositorio real: anotar nada no escribe nada.
    if (avisadas.isNotEmpty) anotaciones++;
    await compuertaAnotar?.future;
    await _real.anotar(avisadas);
  }
}

void main() {
  late InscripcionesConZonaEnMemoria fuente;
  late ZonasAvisadasEnMemoria avisadas;

  ProviderContainer crear({ZonasAvisadasRepository? repositorio}) {
    final container = ProviderContainer(
      overrides: [
        inscripcionesConZonaDataSourceProvider.overrideWithValue(fuente),
        zonasAvisadasRepositoryProvider.overrideWithValue(repositorio ?? avisadas),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Abre el notifier (como lo hace la pantalla principal) y espera a que termine de procesar.
  Future<ProviderContainer> abrir({ZonasAvisadasRepository? repositorio}) async {
    final container = crear(repositorio: repositorio);
    container.listen(avisosZonaProvider(_usuario), (_, _) {});
    await pumpEventQueue();
    return container;
  }

  List<AvisoZona> avisos(ProviderContainer c) => c.read(avisosZonaProvider(_usuario));
  AvisosZona notifier(ProviderContainer c) => c.read(avisosZonaProvider(_usuario).notifier);

  setUp(() {
    fuente = InscripcionesConZonaEnMemoria();
    avisadas = ZonasAvisadasEnMemoria();
  });

  test('dado que el teléfono no tiene inscripciones, no hay avisos', () async {
    final c = await abrir();

    expect(avisos(c), isEmpty);
    expect(await avisadas.leer(), isEmpty);
  });

  test('dado que la inscripción ya viene con zona al abrir la app, cuando se arma, el aviso está '
      'ahí (cambio que llegó con la app cerrada)', () async {
    fuente.publicar([_centro]);

    final c = await abrir();

    expect(avisos(c), [_asignadaCentro]);
  });

  test(
    'dado que la app está abierta, cuando termina un pull con zona nueva, aparece el aviso',
    () async {
      final c = await abrir();
      expect(avisos(c), isEmpty);

      fuente.publicar([_centro]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaCentro]);
    },
  );

  test(
    'dado un aviso pendiente, cuando el mismo pull llega otra vez, sigue un solo aviso',
    () async {
      final c = await abrir();

      fuente.publicar([_centro]);
      await pumpEventQueue();
      fuente.publicar([_centro]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaCentro]);
    },
  );

  test(
    'dado un aviso sin cerrar, cuando la zona vuelve a cambiar, queda solo el último cambio',
    () async {
      fuente.publicar([_centro]);
      final c = await abrir();
      expect(avisos(c), [_asignadaCentro]);

      fuente.publicar([_norte]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaNorte]);
    },
  );

  test(
    'dado un aviso de zona, cuando el coordinador la quita, el aviso pasa a «ya no tenés zona»',
    () async {
      fuente.publicar([_centro]);
      final c = await abrir();
      await notifier(c).cerrar(_asignadaCentro);

      fuente.publicar([_inscripcion()]);
      await pumpEventQueue();

      expect(avisos(c), [_quitada]);
    },
  );

  test(
    'dado que la inscripción llega dada de baja, no hay aviso y queda anotada sin zona',
    () async {
      await avisadas.anotar({'insc-1': 'z-centro'});
      fuente.publicar([_inscripcion(dadaDeBaja: true)]);

      final c = await abrir();

      expect(avisos(c), isEmpty);
      expect(await avisadas.leer(), {'insc-1': null});
    },
  );

  group('cerrar', () {
    test(
      'dado un aviso, cuando la persona lo cierra, desaparece y se anota la zona avisada',
      () async {
        fuente.publicar([_centro]);
        final c = await abrir();

        await notifier(c).cerrar(_asignadaCentro);

        expect(avisos(c), isEmpty);
        expect(await avisadas.leer(), {'insc-1': 'z-centro'});
      },
    );

    test('dado un aviso cerrado, cuando la app se abre de nuevo, no vuelve a salir', () async {
      fuente.publicar([_centro]);
      final primera = await abrir();
      await notifier(primera).cerrar(_asignadaCentro);

      final segunda = await abrir();

      expect(avisos(segunda), isEmpty);
    });

    test('dado un aviso sin cerrar, cuando la app se abre de nuevo, vuelve a salir', () async {
      fuente.publicar([_centro]);
      await abrir();

      final segunda = await abrir();

      expect(avisos(segunda), [_asignadaCentro]);
    });

    test('dado un aviso cerrado, cuando la zona cambia otra vez, el aviso nuevo sale', () async {
      fuente.publicar([_centro]);
      final c = await abrir();
      await notifier(c).cerrar(_asignadaCentro);

      fuente.publicar([_norte]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaNorte]);
    });

    test('dado el doble toque en «Entendido», se anota una sola vez y no pasa nada raro', () async {
      final lento = _RepositorioLento();
      fuente.publicar([_centro]);
      final c = await abrir(repositorio: lento);

      final primero = notifier(c).cerrar(_asignadaCentro);
      final segundo = notifier(c).cerrar(_asignadaCentro);
      await Future.wait([primero, segundo]);

      expect(avisos(c), isEmpty);
      expect(lento.anotaciones, 1);
    });

    test(
      'dado que la zona cambió y se cierra el aviso viejo, el nuevo sigue visible y nada se anota',
      () async {
        fuente.publicar([_centro]);
        final c = await abrir();
        fuente.publicar([_norte]);
        await pumpEventQueue();

        await notifier(c).cerrar(_asignadaCentro);

        expect(avisos(c), [_asignadaNorte]);
        expect(await avisadas.leer(), isEmpty);
      },
    );

    test(
      'dado que el almacén falla al anotar, el aviso cerrado no vuelve a salir en esta sesión',
      () async {
        avisadas.fallaAlAnotar = true;
        fuente.publicar([_centro]);
        final c = await abrir();

        await notifier(c).cerrar(_asignadaCentro);
        expect(avisos(c), isEmpty);
        fuente.publicar([_centro, _inscripcion(id: 'insc-2')]);
        await pumpEventQueue();

        expect(avisos(c), isEmpty);
      },
    );

    test(
      'dado que el almacén falla al anotar, en la próxima sesión el aviso vuelve a salir (nunca se '
      'pierde)',
      () async {
        avisadas.fallaAlAnotar = true;
        fuente.publicar([_centro]);
        final primera = await abrir();
        await notifier(primera).cerrar(_asignadaCentro);

        final segunda = await abrir();

        expect(avisos(segunda), [_asignadaCentro]);
      },
    );

    test('dado que se cierra mientras otro pull se procesa, no se pisan: el cierre gana', () async {
      final lento = _RepositorioLento();
      fuente.publicar([_centro]);
      final c = await abrir(repositorio: lento);
      lento.compuertaAnotar = Completer<void>();

      final cierre = notifier(c).cerrar(_asignadaCentro);
      fuente.publicar([_centro]);
      await pumpEventQueue();
      lento.compuertaAnotar!.complete();
      await cierre;
      await pumpEventQueue();

      expect(avisos(c), isEmpty);
      expect(await lento.leer(), {'insc-1': 'z-centro'});
    });

    test('dado un aviso cerrado y una baja, cuando la inscripción vuelve sin zona, no hay «Ya no '
        'tenés zona» falso, y la primera zona nueva sí se avisa', () async {
      fuente.publicar([_centro]);
      final c = await abrir();
      await notifier(c).cerrar(_asignadaCentro);

      fuente.publicar([_inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro', dadaDeBaja: true)]);
      await pumpEventQueue();
      fuente.publicar([_inscripcion()]);
      await pumpEventQueue();

      expect(avisos(c), isEmpty);

      fuente.publicar([_centro]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaCentro]);
    });

    test('dado que se cierra un aviso mientras otro pull anota en silencio, el aviso cerrado no '
        'reaparece', () async {
      final lento = _RepositorioLento();
      fuente.publicar([_centro]);
      final c = await abrir(repositorio: lento);
      lento.compuertaAnotar = Completer<void>();

      fuente.publicar([_centro, _inscripcion(id: 'insc-2')]);
      await pumpEventQueue();
      final cierre = notifier(c).cerrar(_asignadaCentro);
      lento.compuertaAnotar!.complete();
      await cierre;
      await pumpEventQueue();

      expect(avisos(c), isEmpty);
      expect(await lento.leer(), {'insc-1': 'z-centro', 'insc-2': null});
    });

    test('dado que hay avisos de varias campañas, cerrar uno deja los demás', () async {
      fuente.publicar([_centro, _inscripcion(id: 'insc-2', zonaId: 'z-sur', zonaNombre: 'Sur')]);
      final c = await abrir();
      expect(avisos(c), hasLength(2));

      await notifier(c).cerrar(_asignadaCentro);

      expect(avisos(c).single.inscripcionId, 'insc-2');
    });
  });

  group('cuando algo falla', () {
    test(
      'dado un error al leer las inscripciones, los avisos que había se mantienen y no lanza',
      () async {
        fuente.publicar([_centro]);
        final c = await abrir();

        fuente.fallar(StateError('lectura rota'));
        await pumpEventQueue();

        expect(avisos(c), [_asignadaCentro]);
      },
    );

    test('dado un error al arrancar, no hay avisos y un pull posterior los arma', () async {
      fuente.falla = StateError('lectura rota');
      final c = await abrir();
      expect(avisos(c), isEmpty);

      fuente.falla = null;
      fuente.publicar([_centro]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaCentro]);
    });

    test('dado que el notifier se descarta con un pull en vuelo, no lanza al terminar', () async {
      final lento = _RepositorioLento()..compuertaAnotar = Completer<void>();
      fuente.publicar([_inscripcion()]);
      final container = ProviderContainer(
        overrides: [
          inscripcionesConZonaDataSourceProvider.overrideWithValue(fuente),
          zonasAvisadasRepositoryProvider.overrideWithValue(lento),
        ],
      );
      final suscripcion = container.listen(avisosZonaProvider(_usuario), (_, _) {});
      await pumpEventQueue();

      suscripcion.close();
      await pumpEventQueue();
      lento.compuertaAnotar!.complete();
      await pumpEventQueue();
      container.dispose();

      expect(lento.anotaciones, 1);
    });

    test('dado que se descarta el notifier, deja de escuchar la fuente', () async {
      final container = crear();
      final suscripcion = container.listen(avisosZonaProvider(_usuario), (_, _) {});
      await pumpEventQueue();
      expect(fuente.suscripciones, 1);

      suscripcion.close();
      await pumpEventQueue();
      fuente.publicar([_inscripcion()]);
      await pumpEventQueue();

      // Si siguiera escuchando, anotaría la inscripción sin zona.
      expect(await avisadas.leer(), isEmpty);
    });
  });

  test(
    'dos pulls seguidos sin esperar se procesan en orden: el estado final es el del último',
    () async {
      final lento = _RepositorioLento();
      final c = await abrir(repositorio: lento);

      fuente.publicar([_centro]);
      fuente.publicar([_norte]);
      await pumpEventQueue();

      expect(avisos(c), [_asignadaNorte]);
    },
  );
}
