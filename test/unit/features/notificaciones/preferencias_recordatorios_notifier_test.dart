// HU-NOT-004 / issue #415 — el estado de las preferencias de los recordatorios: leer, cambiar con el
// cambio a la vista, guardar de a uno sin perder ninguno y volver atrás si no se puede guardar.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/agendas_para_recordar_falsas.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

void main() {
  late PreferenciasRecordatoriosRepositoryEnMemoria repositorio;
  late RecordatoriosEnMemoria recordatorios;
  late AgendasParaRecordarEnMemoria agendas;
  final sesion = Sesion(
    usuarioId: 'col-1',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );

  setUp(() {
    repositorio = PreferenciasRecordatoriosRepositoryEnMemoria();
    recordatorios = RecordatoriosEnMemoria();
    agendas = AgendasParaRecordarEnMemoria([
      for (final n in [1, 2, 3])
        RecordatorioDeVisita(
          agendaId: 'ag-$n',
          tipo: TipoAgenda.entrevista,
          direccion: 'Av. Italia 1234',
          fechaProgramada: DateTime.now().add(Duration(days: n)),
        ),
    ]);
  });

  ProviderContainer armar({Sesion? conSesion}) {
    final c = ProviderContainer(
      overrides: [
        preferenciasRecordatoriosRepositoryProvider.overrideWithValue(repositorio),
        recordatoriosProvider.overrideWithValue(recordatorios),
        agendasParaRecordarProvider.overrideWithValue(agendas),
        sesionProvider.overrideWith(() => _SesionFija(conSesion ?? sesion)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// El provider vivo (como lo mira la pantalla) y su estado ya leído.
  Future<(ProviderContainer, ProviderSubscription<AsyncValue<EstadoPreferenciasRecordatorios>>)>
  abrir({Sesion? conSesion}) async {
    final c = armar(conSesion: conSesion);
    await c.read(sesionProvider.future);
    final lectura = c.listen(preferenciasRecordatoriosProvider, (_, _) {});
    await c.read(preferenciasRecordatoriosProvider.future);
    return (c, lectura);
  }

  PreferenciasRecordatorios vista(ProviderContainer c) =>
      c.read(preferenciasRecordatoriosProvider).requireValue.preferencias;

  group('leer', () {
    test(
      'dado que nunca eligió nada, arranca con los recordatorios prendidos a 30 minutos',
      () async {
        final (c, _) = await abrir();

        expect(vista(c), const PreferenciasRecordatorios());
        expect(c.read(preferenciasRecordatoriosProvider).requireValue.falla, isNull);
      },
    );

    test('dado lo guardado, lo muestra', () async {
      repositorio.preferencias = const PreferenciasRecordatorios(
        activados: false,
        anticipacionMinutos: 90,
      );

      final (c, _) = await abrir();

      expect(vista(c).activados, isFalse);
      expect(vista(c).anticipacionMinutos, 90);
    });

    test('dado que el almacén falla, queda en error sin reintentar solo', () async {
      repositorio.fallaAlLeer = true;
      final c = armar();
      final lectura = c.listen(preferenciasRecordatoriosProvider, (_, _) {});
      await c.read(preferenciasRecordatoriosProvider.future).then((_) {}, onError: (_) {});

      expect(c.read(preferenciasRecordatoriosProvider).hasError, isTrue);
      lectura.close();
    });
  });

  group('cambiar', () {
    test(
      'dado un cambio de anticipación, se ve enseguida y después queda guardado, con la cantidad '
      'de recordatorios reprogramados',
      () async {
        final (c, _) = await abrir();
        repositorio.guardadoDemorado = Completer<void>();

        final futuro = c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(60);
        await Future<void>.delayed(Duration.zero);
        expect(vista(c).anticipacionMinutos, 60, reason: 'se ve antes de estar guardado');
        expect(repositorio.preferencias.anticipacionMinutos, 30);
        repositorio.guardadoDemorado!.complete();

        expect(await futuro, 3);
        expect(repositorio.preferencias.anticipacionMinutos, 60);
        expect(recordatorios.llamadas.where((l) => l.startsWith('programar')), hasLength(3));
      },
    );

    test(
      'dado que apago los recordatorios, queda guardado y el interruptor sigue apagado',
      () async {
        final (c, _) = await abrir();

        await c.read(preferenciasRecordatoriosProvider.notifier).cambiarActivados(activados: false);

        expect(vista(c).activados, isFalse);
        expect(repositorio.preferencias.activados, isFalse);
      },
    );

    test('dado un valor fuera de rango, se guarda acotado', () async {
      final (c, _) = await abrir();

      await c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(500);

      expect(repositorio.preferencias.anticipacionMinutos, 120);
    });

    test(
      'dado que no se puede guardar, el control vuelve a como estaba y queda el error con lo que '
      'se quiso',
      () async {
        final (c, _) = await abrir();
        repositorio.fallaAlGuardar = true;

        final r = await c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(60);

        expect(r, isNull);
        expect(vista(c).anticipacionMinutos, 30);
        expect(
          c.read(preferenciasRecordatoriosProvider).requireValue.falla,
          const PreferenciasRecordatorios(anticipacionMinutos: 60),
        );
      },
    );

    test('dado el error de guardar, cuando se reintenta y esta vez anda, queda guardado y el error '
        'desaparece', () async {
      final (c, _) = await abrir();
      repositorio.fallaAlGuardar = true;
      final notificador = c.read(preferenciasRecordatoriosProvider.notifier);
      await notificador.cambiarAnticipacion(60);
      repositorio.fallaAlGuardar = false;

      final r = await notificador.reintentar();

      expect(r, 3);
      expect(vista(c).anticipacionMinutos, 60);
      expect(c.read(preferenciasRecordatoriosProvider).requireValue.falla, isNull);
    });

    test('dado que no hay nada que reintentar, reintentar no hace nada', () async {
      final (c, _) = await abrir();

      expect(await c.read(preferenciasRecordatoriosProvider.notifier).reintentar(), isNull);
      expect(repositorio.guardados, isEmpty);
    });

    test('dado el error de guardar, cuando la persona hace otro cambio, el error se va', () async {
      final (c, _) = await abrir();
      repositorio.fallaAlGuardar = true;
      final notificador = c.read(preferenciasRecordatoriosProvider.notifier);
      await notificador.cambiarAnticipacion(60);
      repositorio.fallaAlGuardar = false;

      final futuro = notificador.cambiarActivados(activados: false);

      expect(c.read(preferenciasRecordatoriosProvider).requireValue.falla, isNull);
      await futuro;
    });

    test(
      'dado que no se pueden leer las agendas, el cambio de anticipación vuelve atrás',
      () async {
        final (c, _) = await abrir();
        agendas.falla = true;

        final r = await c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(60);

        expect(r, isNull);
        expect(vista(c).anticipacionMinutos, 30);
        expect(repositorio.preferencias.anticipacionMinutos, 30);
      },
    );

    test('dado que volvió al valor de antes, no guarda nada', () async {
      final (c, _) = await abrir();

      final r = await c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(30);

      expect(r, isNull);
      expect(repositorio.guardados, isEmpty);
    });

    test('dado que no hay sesión, se guarda igual y no se reprograma nada', () async {
      final c = ProviderContainer(
        overrides: [
          preferenciasRecordatoriosRepositoryProvider.overrideWithValue(repositorio),
          recordatoriosProvider.overrideWithValue(recordatorios),
          agendasParaRecordarProvider.overrideWithValue(agendas),
          sesionProvider.overrideWith(() => _SesionFija(null)),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);
      c.listen(preferenciasRecordatoriosProvider, (_, _) {});
      await c.read(preferenciasRecordatoriosProvider.future);

      final r = await c.read(preferenciasRecordatoriosProvider.notifier).cambiarAnticipacion(60);

      expect(r, 0);
      expect(agendas.consultas, 0);
      expect(repositorio.preferencias.anticipacionMinutos, 60);
    });
  });

  group('dos acciones seguidas', () {
    test(
      'dado un guardado en curso, cuando llega otro cambio, se guarda también el último y ninguno '
      'se pierde',
      () async {
        final (c, _) = await abrir();
        final notificador = c.read(preferenciasRecordatoriosProvider.notifier);
        repositorio.guardadoDemorado = Completer<void>();

        final primero = notificador.cambiarAnticipacion(60);
        await Future<void>.delayed(Duration.zero);
        final segundo = notificador.cambiarActivados(activados: false);
        final tercero = notificador.cambiarAnticipacion(90);
        repositorio.guardadoDemorado!.complete();
        await Future.wait([primero, segundo, tercero]);

        expect(
          repositorio.preferencias,
          const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 90),
        );
        expect(vista(c), repositorio.preferencias);
      },
    );

    test('dado el mismo cambio pedido dos veces (doble toque), se guarda una sola vez', () async {
      final (c, _) = await abrir();
      final notificador = c.read(preferenciasRecordatoriosProvider.notifier);

      await Future.wait([
        notificador.cambiarActivados(activados: false),
        notificador.cambiarActivados(activados: false),
      ]);

      expect(repositorio.guardados, ['activados:false']);
    });

    test('dado un cambio y su contrario enseguida, termina en lo último', () async {
      final (c, _) = await abrir();
      final notificador = c.read(preferenciasRecordatoriosProvider.notifier);

      await Future.wait([
        notificador.cambiarActivados(activados: false),
        notificador.cambiarActivados(activados: true),
      ]);

      expect(repositorio.preferencias.activados, isTrue);
      expect(vista(c).activados, isTrue);
    });

    test(
      'dado un guardado que falla con otro pedido detrás, vuelve a lo guardado de verdad',
      () async {
        final (c, _) = await abrir();
        final notificador = c.read(preferenciasRecordatoriosProvider.notifier);
        repositorio
          ..guardadoDemorado = Completer<void>()
          ..fallaAlGuardar = true;

        final primero = notificador.cambiarAnticipacion(60);
        await Future<void>.delayed(Duration.zero);
        final segundo = notificador.cambiarAnticipacion(90);
        repositorio.guardadoDemorado!.complete();
        await Future.wait([primero, segundo]);

        expect(vista(c), const PreferenciasRecordatorios());
        expect(repositorio.preferencias, const PreferenciasRecordatorios());
      },
    );
  });

  group('volver atrás y reentrar', () {
    test('dado un guardado en curso, cuando la persona sale de la pantalla, se termina de guardar '
        'igual', () async {
      final (c, lectura) = await abrir();
      final notificador = c.read(preferenciasRecordatoriosProvider.notifier);
      repositorio.guardadoDemorado = Completer<void>();

      final futuro = notificador.cambiarAnticipacion(60);
      await Future<void>.delayed(Duration.zero);
      lectura.close();
      await Future<void>.delayed(Duration.zero);
      repositorio.guardadoDemorado!.complete();

      expect(await futuro, 3);
      expect(repositorio.preferencias.anticipacionMinutos, 60);
    });

    test('dado que volvió a entrar, lee lo que quedó guardado', () async {
      final (c, lectura) = await abrir();
      await c.read(preferenciasRecordatoriosProvider.notifier).cambiarActivados(activados: false);
      lectura.close();
      await Future<void>.delayed(Duration.zero);

      c.listen(preferenciasRecordatoriosProvider, (_, _) {});
      await c.read(preferenciasRecordatoriosProvider.future);

      expect(vista(c).activados, isFalse);
    });
  });
}
