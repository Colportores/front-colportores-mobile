// «Aviso exacto» (HU-NOT-002, #510): el permiso «Alarmas y recordatorios» se lee al abrir la app y al
// volver a ella, y cada vez que cambia —y al leerlo por primera vez— los recordatorios de las visitas
// pendientes se reprograman (exactos con el permiso prendido; de nuevo inexactos si se quitó).
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/fakes/permiso_alarmas_exactas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/alarmas_exactas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/agendas_para_recordar_falsas.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2030),
);

/// Sale de la app y vuelve (por ejemplo, a los ajustes del teléfono y de regreso).
void _volverALaApp(TestWidgetsFlutterBinding binding) {
  for (final estado in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    binding.handleAppLifecycleStateChanged(estado);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late PermisoAlarmasExactasEnMemoria alarmas;
  late AgendasParaRecordarEnMemoria agendas;
  late RecordatoriosEnMemoria recordatorios;

  setUp(() {
    alarmas = PermisoAlarmasExactasEnMemoria();
    agendas = AgendasParaRecordarEnMemoria([
      RecordatorioDeVisita(
        agendaId: 'ag-1',
        tipo: TipoAgenda.entrevista,
        direccion: 'Av. Italia 1234',
        fechaProgramada: DateTime.now().add(const Duration(days: 1)),
      ),
      RecordatorioDeVisita(
        agendaId: 'ag-2',
        tipo: TipoAgenda.cobranza,
        direccion: 'Bulevar Artigas 100',
        fechaProgramada: DateTime.now().add(const Duration(days: 2)),
      ),
    ]);
    recordatorios = RecordatoriosEnMemoria();
  });

  /// El contenedor con el provider vivo (como lo mantiene la pantalla principal).
  Future<ProviderContainer> abrir({Sesion? sesion}) async {
    final c = ProviderContainer(
      overrides: [
        permisoAlarmasExactasProvider.overrideWithValue(alarmas),
        agendasParaRecordarProvider.overrideWithValue(agendas),
        recordatoriosProvider.overrideWithValue(recordatorios),
        sesionProvider.overrideWith(() => _SesionFija(sesion ?? _sesion)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(alarmasExactasProvider, (_, _) {});
    await c.read(sesionProvider.future);
    await c.read(alarmasExactasProvider.future);
    await pumpEventQueue();
    return c;
  }

  EstadoAlarmasExactas? estado(ProviderContainer c) => c.read(alarmasExactasProvider).value;

  group('al abrir la app', () {
    test('dado «Alarmas y recordatorios» apagado, se lee y los recordatorios se vuelven a '
        'programar', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;

      final c = await abrir();

      expect(estado(c), EstadoAlarmasExactas.apagadas);
      expect(agendas.consultas, 1);
      expect(agendas.ultimoColportor, 'col-1');
      expect(recordatorios.llamadas, ['programar:ag-1', 'programar:ag-2']);
    });

    test(
      'dado el permiso prendido, los recordatorios se vuelven a programar (ahora exactos)',
      () async {
        alarmas.estado = EstadoAlarmasExactas.permitidas;

        final c = await abrir();

        expect(estado(c), EstadoAlarmasExactas.permitidas);
        expect(recordatorios.llamadas, ['programar:ag-1', 'programar:ag-2']);
      },
    );

    test('dado un sistema sin ese permiso (iOS), no se reprograma nada', () async {
      alarmas.estado = EstadoAlarmasExactas.noAplica;

      final c = await abrir();

      expect(estado(c), EstadoAlarmasExactas.noAplica);
      expect(agendas.consultas, 0);
      expect(recordatorios.llamadas, isEmpty);
    });

    test(
      'dado que el sistema no contesta, queda en noAplica (sin aviso) y no reprograma',
      () async {
        alarmas.fallaAlLeer = true;

        final c = await abrir();

        expect(c.read(alarmasExactasProvider).hasError, isFalse);
        expect(estado(c), EstadoAlarmasExactas.noAplica);
        expect(agendas.consultas, 0);
      },
    );

    test('dado que no hay sesión, no hay agendas que reprogramar', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      final c = ProviderContainer(
        overrides: [
          permisoAlarmasExactasProvider.overrideWithValue(alarmas),
          agendasParaRecordarProvider.overrideWithValue(agendas),
          recordatoriosProvider.overrideWithValue(recordatorios),
          sesionProvider.overrideWith(() => _SesionFija(null)),
        ],
      );
      addTearDown(c.dispose);
      c.listen(alarmasExactasProvider, (_, _) {});
      await c.read(sesionProvider.future);
      await c.read(alarmasExactasProvider.future);
      await pumpEventQueue();

      expect(estado(c), EstadoAlarmasExactas.apagadas);
      expect(agendas.consultas, 0);
    });

    test(
      'dado que las agendas no se pueden leer, el permiso igual se muestra y la app sigue',
      () async {
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        agendas.falla = true;

        final c = await abrir();

        expect(estado(c), EstadoAlarmasExactas.apagadas);
        expect(agendas.consultas, 1);
      },
    );
  });

  group('al volver a la app', () {
    test('dado que prendió el permiso en los ajustes, el aviso se va y los recordatorios se '
        'reprograman', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      final c = await abrir();
      recordatorios.llamadas.clear();

      alarmas.estado = EstadoAlarmasExactas.permitidas;
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(estado(c), EstadoAlarmasExactas.permitidas);
      expect(agendas.consultas, 2);
      expect(recordatorios.llamadas, ['programar:ag-1', 'programar:ag-2']);
    });

    test('dado que quitó el permiso, el aviso vuelve y los recordatorios se reprograman '
        '(Android cancela las alarmas exactas al quitarlo)', () async {
      alarmas.estado = EstadoAlarmasExactas.permitidas;
      final c = await abrir();
      recordatorios.llamadas.clear();

      alarmas.estado = EstadoAlarmasExactas.apagadas;
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(estado(c), EstadoAlarmasExactas.apagadas);
      expect(recordatorios.llamadas, ['programar:ag-1', 'programar:ag-2']);
    });

    test('dado que no cambió nada, no se reprograma otra vez', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      final c = await abrir();

      _volverALaApp(binding);
      await pumpEventQueue();
      _volverALaApp(binding);
      await pumpEventQueue();

      expect(estado(c), EstadoAlarmasExactas.apagadas);
      expect(alarmas.lecturas, 3);
      expect(agendas.consultas, 1);
    });

    test('dado dos regresos seguidos mientras el sistema contesta, se lee una sola vez', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      final c = await abrir();
      final lecturasAntes = alarmas.lecturas;
      final demora = alarmas.lecturaDemorada = Completer<void>();
      alarmas.estado = EstadoAlarmasExactas.permitidas;

      _volverALaApp(binding);
      _volverALaApp(binding);
      await pumpEventQueue();
      demora.complete();
      await pumpEventQueue();

      expect(alarmas.lecturas - lecturasAntes, 1);
      expect(estado(c), EstadoAlarmasExactas.permitidas);
      expect(agendas.consultas, 2);
    });

    test(
      'dado que no puede leer el permiso al volver, deja lo que había y no reprograma',
      () async {
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        final c = await abrir();

        alarmas.fallaAlLeer = true;
        alarmas.estado = EstadoAlarmasExactas.permitidas;
        _volverALaApp(binding);
        await pumpEventQueue();

        expect(estado(c), EstadoAlarmasExactas.apagadas);
        expect(agendas.consultas, 1);
      },
    );

    test(
      'dado que al abrir no se pudo leer, la próxima lectura buena lo muestra y reprograma',
      () async {
        alarmas.fallaAlLeer = true;
        final c = await abrir();
        expect(estado(c), EstadoAlarmasExactas.noAplica);

        alarmas.fallaAlLeer = false;
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        _volverALaApp(binding);
        await pumpEventQueue();

        expect(estado(c), EstadoAlarmasExactas.apagadas);
        expect(agendas.consultas, 1);
      },
    );

    test(
      'dado un cambio mientras se reprograma, no se pisan: al terminar se hace otra pasada',
      () async {
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        final demora = agendas.demora = Completer<void>();
        final c = ProviderContainer(
          overrides: [
            permisoAlarmasExactasProvider.overrideWithValue(alarmas),
            agendasParaRecordarProvider.overrideWithValue(agendas),
            recordatoriosProvider.overrideWithValue(recordatorios),
            sesionProvider.overrideWith(() => _SesionFija(_sesion)),
          ],
        );
        addTearDown(c.dispose);
        c.listen(alarmasExactasProvider, (_, _) {});
        await c.read(sesionProvider.future);
        await c.read(alarmasExactasProvider.future);
        await pumpEventQueue();
        expect(agendas.consultas, 1);

        alarmas.estado = EstadoAlarmasExactas.permitidas;
        _volverALaApp(binding);
        await pumpEventQueue();
        expect(agendas.consultas, 1, reason: 'la primera pasada sigue en curso');

        demora.complete();
        await pumpEventQueue();

        expect(agendas.consultas, 2);
        expect(estado(c), EstadoAlarmasExactas.permitidas);
      },
    );
  });

  group('abrirAjustes', () {
    test('abre «Alarmas y recordatorios» y devuelve true', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      final c = await abrir();

      expect(await c.read(alarmasExactasProvider.notifier).abrirAjustes(), isTrue);
      expect(alarmas.ajustesAbiertos, 1);
    });

    test('si el teléfono no tiene esa pantalla devuelve false', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      alarmas.puedeAbrirAjustes = false;
      final c = await abrir();

      expect(await c.read(alarmasExactasProvider.notifier).abrirAjustes(), isFalse);
    });

    test('si la plataforma falla devuelve false y no lanza', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      alarmas.fallaAlAbrir = true;
      final c = await abrir();

      expect(await c.read(alarmasExactasProvider.notifier).abrirAjustes(), isFalse);
    });
  });
}
