// HU-NOT-003 (#187) — recibir las push remotas contra la DB real (en memoria): se guardan en el
// historial una sola vez, se avisan con la app al frente, abren su aviso al tocarlas y las que traen
// datos personales se descartan dejando constancia en el `audit_log` local.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/push_remotas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/auditoria_push_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/historial_notificaciones_falsos.dart';
import '../../../helpers/logger_mudo.dart';

const _pedido = '3f2b8c1e-9a4d-4e7b-8c1a-5d6e7f8a9b0c';
const _otroPedido = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
const _evento = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

final _ahora = DateTime.utc(2026, 11, 9, 15, 30);

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;

  void publicar(AppDatabase db) => state = db;
}

/// Un abridor que anota qué avisos abrió y puede fallar o esperar.
final class _Abridor {
  final abiertos = <Notificacion>[];
  Object? falla;
  Completer<void>? puerta;

  Future<void> call(Notificacion aviso) async {
    abiertos.add(aviso);
    final p = puerta;
    if (p != null) await p.future;
    if (falla case final error?) throw error;
  }
}

final class _AuditoriaQueFalla implements AuditoriaPushRepository {
  @override
  Future<void> registrarDatosPersonales({
    required List<String> campos,
    required DateTime ahora,
  }) async => throw StateError('disco lleno');
}

Map<String, Object?> _pedidoAutorizado({String pedido = _pedido, String? evento}) => {
  'type': 'pedido_autorizado',
  'pedido_id': pedido,
  'event_id': ?evento,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late PushRemotasEnMemoria push;
  late _Abridor abridor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    push = PushRemotasEnMemoria();
    abridor = _Abridor();
  });
  tearDown(() => db.close());

  Future<void> asentar() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// La escucha armada, con lo que sale al aviso de arriba anotado en [mostrados].
  ({ProviderContainer c, List<Notificacion> mostrados, ProviderSubscription<void> escucha}) armar({
    bool conDb = true,
    List<Override> mas = const [],
  }) {
    final c = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(conDb ? db : null)),
        pushRemotasProvider.overrideWithValue(push),
        abridorAvisoPushProvider.overrideWithValue(abridor.call),
        relojHistorialNotificacionesProvider.overrideWithValue(() => _ahora),
        ...mas,
      ],
    );
    addTearDown(c.dispose);
    final mostrados = <Notificacion>[];
    final escucha = c.listen(escuchaPushRemotasProvider, (_, _) {});
    c.read(canalAvisosPushProvider).avisos.listen(mostrados.add);
    return (c: c, mostrados: mostrados, escucha: escucha);
  }

  Future<List<NotificacionFila>> historial() => db.select(db.notificacionesHistorial).get();
  Future<List<AuditLogFila>> auditoria() => db.select(db.auditLogLocal).get();

  group('con la app al frente (24C·08)', () {
    test('dado un pedido autorizado, cuando llega, entonces queda en el historial y sale el aviso '
        'de arriba con el texto que arma la app', () async {
      final a = armar();
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento));
      await asentar();

      final guardadas = await historial();
      expect(guardadas, hasLength(1));
      expect(guardadas.single.id, 'push-$_evento');
      expect(guardadas.single.tipo, TipoNotificacion.pedidoAutorizado.codigo);
      expect(guardadas.single.titulo, 'Tu pedido fue autorizado');
      expect(guardadas.single.leidaEn, isNull);
      expect(a.mostrados.map((n) => n.titulo), ['Tu pedido fue autorizado']);
      expect(abridor.abiertos, isEmpty, reason: 'con la app al frente no se abre nada solo');
    });

    test(
      'dado el mismo evento recibido dos veces, entonces se guarda y se avisa una sola vez',
      () async {
        final a = armar();
        await asentar();

        push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento));
        push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento));
        await asentar();
        push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento.toUpperCase()));
        await asentar();

        expect(await historial(), hasLength(1));
        expect(a.mostrados, hasLength(1));
      },
    );

    test('dado el payload del ejemplo (sin event_id) repetido, entonces tampoco duplica', () async {
      final a = armar();
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado());
      push.llegaConLaAppAbierta(_pedidoAutorizado());
      await asentar();

      expect(await historial(), hasLength(1));
      expect(a.mostrados, hasLength(1));
    });

    test('dado dos pedidos distintos seguidos, entonces se guardan los dos y se avisan en el orden '
        'en que llegaron', () async {
      final a = armar();
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado(pedido: _pedido));
      push.llegaConLaAppAbierta(_pedidoAutorizado(pedido: _otroPedido));
      await asentar();

      expect(await historial(), hasLength(2));
      expect(a.mostrados.map((n) => n.id), [
        'push-pedido_autorizado:$_pedido',
        'push-pedido_autorizado:$_otroPedido',
      ]);
    });

    test('dado que guardar falla en la primera, cuando llega la segunda, entonces la segunda se '
        'atiende igual y la primera no queda a medias', () async {
      final historialQueFalla = HistorialEnMemoria()
        ..prefijoQueFallaAlRegistrar = 'push-pedido_autorizado:$_pedido';
      final a = armar(
        mas: [historialNotificacionesRepositoryProvider.overrideWithValue(historialQueFalla)],
      );
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado(pedido: _pedido));
      push.llegaConLaAppAbierta(_pedidoAutorizado(pedido: _otroPedido));
      await asentar();

      expect(historialQueFalla.filas.map((n) => n.id), ['push-pedido_autorizado:$_otroPedido']);
      expect(a.mostrados.map((n) => n.id), ['push-pedido_autorizado:$_otroPedido']);
    });
  });

  group('datos personales (R-NO02)', () {
    test('dado un payload con el nombre de un cliente, cuando llega, entonces no se guarda ni se '
        'avisa y queda `push_pii_detected` en el audit_log local, sin el valor', () async {
      final a = armar();
      await asentar();

      push.llegaConLaAppAbierta({
        ..._pedidoAutorizado(evento: _evento),
        'cliente_nombre': 'María Fernández',
      });
      await asentar();

      expect(await historial(), isEmpty);
      expect(a.mostrados, isEmpty);
      final filas = await auditoria();
      expect(filas, hasLength(1));
      expect(filas.single.evento, 'push_pii_detected');
      expect(filas.single.uuid, EventoAuditoriaLocal.uuidPush);
      expect(filas.single.motivo, 'cliente_nombre');
      expect(filas.single.creadoEn, _ahora);
    });

    test('dado que el payload con datos personales viene del toque de una notificación, entonces '
        'tampoco se abre nada', () async {
      armar();
      await asentar();

      push.seTocaConLaAppEnSegundoPlano({..._pedidoAutorizado(), 'telefono': '11 5555-1234'});
      await asentar();

      expect(abridor.abiertos, isEmpty);
      expect(await historial(), isEmpty);
      expect(await auditoria(), hasLength(1));
    });

    test('dado que la auditoría no se puede escribir, entonces igual se descarta y lo que viene '
        'después se atiende', () async {
      final a = armar(
        mas: [auditoriaPushRepositoryProvider.overrideWithValue(_AuditoriaQueFalla())],
      );
      await asentar();

      push.llegaConLaAppAbierta({..._pedidoAutorizado(), 'direccion': 'Av. Italia 2810'});
      push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento));
      await asentar();

      expect(await historial(), hasLength(1));
      expect(a.mostrados, hasLength(1));
    });
  });

  group('lo que no se puede usar', () {
    test('dado un tipo que esta versión no conoce, entonces no se guarda, no se avisa y no se '
        'audita', () async {
      final a = armar();
      await asentar();

      push.llegaConLaAppAbierta({'type': 'tipo_del_futuro', 'algo_id': _pedido});
      await asentar();

      expect(await historial(), isEmpty);
      expect(await auditoria(), isEmpty);
      expect(a.mostrados, isEmpty);
    });
  });

  group('al tocar la notificación del sistema (R-NO05)', () {
    test('dado que la app estaba en segundo plano, cuando se toca, entonces el aviso queda en el '
        'historial y se abre, sin aviso de arriba', () async {
      final a = armar();
      await asentar();

      push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(evento: _evento));
      await asentar();

      expect(await historial(), hasLength(1));
      expect(abridor.abiertos.map((n) => n.id), ['push-$_evento']);
      expect(a.mostrados, isEmpty);
    });

    test('dado que el aviso ya estaba en el historial, cuando se toca la notificación, entonces se '
        'abre igual y no se duplica', () async {
      armar();
      await asentar();
      push.llegaConLaAppAbierta(_pedidoAutorizado(evento: _evento));
      await asentar();

      push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(evento: _evento));
      await asentar();

      expect(await historial(), hasLength(1));
      expect(abridor.abiertos.map((n) => n.id), ['push-$_evento']);
    });

    test('dado que la app estaba cerrada y la abrió el toque, cuando arranca la escucha, entonces '
        'se abre una sola vez aunque la escucha se arme de nuevo', () async {
      push.abrirLaAppConElToque(_pedidoAutorizado(evento: _evento));
      final a = armar();
      await asentar();

      expect(abridor.abiertos.map((n) => n.id), ['push-$_evento']);
      expect(await historial(), hasLength(1));

      a.c.invalidate(escuchaPushRemotasProvider);
      await asentar();

      expect(abridor.abiertos, hasLength(1));
      expect(push.consultasDeLaQueAbrioLaApp, 2);
    });

    test(
      'dado que abrir el aviso falla, cuando llega otro toque, entonces el siguiente se atiende',
      () async {
        armar();
        await asentar();
        abridor.falla = StateError('sin pantalla');

        push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(pedido: _pedido));
        await asentar();
        abridor.falla = null;
        push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(pedido: _otroPedido));
        await asentar();

        expect(abridor.abiertos, hasLength(2));
        expect(await historial(), hasLength(2));
      },
    );

    test('dado un toque mientras el anterior sigue abriéndose, entonces se atienden de a uno y en '
        'orden', () async {
      armar();
      await asentar();
      abridor.puerta = Completer<void>();

      push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(pedido: _pedido));
      push.seTocaConLaAppEnSegundoPlano(_pedidoAutorizado(pedido: _otroPedido));
      await asentar();
      expect(abridor.abiertos, hasLength(1), reason: 'el segundo espera a que termine el primero');

      abridor.puerta!.complete();
      await asentar();

      expect(abridor.abiertos.map((n) => n.id), [
        'push-pedido_autorizado:$_pedido',
        'push-pedido_autorizado:$_otroPedido',
      ]);
    });
  });

  group('cuándo escucha', () {
    test('dado que la base no está abierta, cuando llega una push, entonces no se guarda ni tira '
        'nada; cuando se abre, la siguiente sí se guarda', () async {
      final a = armar(conDb: false);
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado());
      await asentar();
      expect(a.mostrados, isEmpty);

      (a.c.read(dbLocalProvider.notifier) as _DbFija).publicar(db);
      await asentar();
      push.llegaConLaAppAbierta(_pedidoAutorizado());
      await asentar();

      expect(a.mostrados, hasLength(1));
      expect(await historial(), hasLength(1));
    });

    test('dado que la pantalla principal se va (cierre de sesión), entonces lo que llega después '
        'no se guarda', () async {
      final a = armar();
      await asentar();
      a.escucha.close();
      await asentar();

      push.llegaConLaAppAbierta(_pedidoAutorizado());
      await asentar();

      expect(await historial(), isEmpty);
    });
  });
}
