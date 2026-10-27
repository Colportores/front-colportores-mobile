// El dominio del historial de avisos (HU-NOT-005, #156): la entidad, el destino de un aviso y los
// casos de uso, sin base de datos.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../helpers/historial_notificaciones_falsos.dart';

void main() {
  group('Notificacion', () {
    test('guarda los instantes en UTC y al milisegundo', () {
      final n = Notificacion(
        id: 'n-1',
        tipo: TipoNotificacion.recordatorioVisita,
        titulo: 'Cobranza a las 16:00',
        recibidaEn: DateTime(2026, 10, 23, 15, 30, 0, 123, 456),
        leidaEn: DateTime(2026, 10, 23, 16, 0, 0, 5, 999),
      );

      expect(n.recibidaEn.isUtc, isTrue);
      expect(n.recibidaEn.microsecond, 0);
      expect(n.leidaEn!.isUtc, isTrue);
      expect(n.leidaEn!.microsecond, 0);
    });

    test('está leída solo si tiene el momento en que se leyó', () {
      expect(aviso('a').leida, isFalse);
      expect(aviso('a', leida: true).leida, isTrue);
    });

    test('dos avisos con los mismos datos son iguales', () {
      expect(aviso('a'), aviso('a'));
      expect(aviso('a'), isNot(aviso('a', leida: true)));
    });
  });

  group('TipoNotificacion', () {
    test('cada código vuelve a su tipo', () {
      for (final t in TipoNotificacion.values) {
        expect(TipoNotificacion.desdeCodigo(t.codigo), t);
      }
    });

    test('un código que no existe es un error de programación', () {
      expect(() => TipoNotificacion.desdeCodigo('PEDIDO_AUTORIZADO'), throwsArgumentError);
    });
  });

  group('DestinoNotificacion', () {
    test('el enlace de una agenda vuelve a la misma agenda', () {
      const destino = DestinoAgenda('0192-abc');

      expect(destino.enlace, 'agenda/0192-abc');
      expect(DestinoNotificacion.desdeEnlace(destino.enlace), destino);
    });

    test('sin enlace, vacío o de algo que no se conoce, no lleva a ningún lado', () {
      expect(DestinoNotificacion.desdeEnlace(null), isNull);
      expect(DestinoNotificacion.desdeEnlace(''), isNull);
      expect(DestinoNotificacion.desdeEnlace('agenda/'), isNull);
      expect(DestinoNotificacion.desdeEnlace('pedido/123'), isNull);
    });
  });

  group('RegistrarNotificacionUseCase', () {
    late HistorialEnMemoria historial;
    late RegistrarNotificacionUseCase registrar;
    setUp(() {
      historial = HistorialEnMemoria();
      registrar = RegistrarNotificacionUseCase(historial, ahora: () => ahoraDelCentro);
    });

    test('guarda un aviso y dice que era nuevo', () async {
      expect(await registrar(aviso('a')), const Right<Failure, bool>(true));
      expect(historial.filas.map((n) => n.id), ['a']);
    });

    test('el mismo aviso otra vez no se guarda dos veces', () async {
      await registrar(aviso('a'));

      expect(await registrar(aviso('a')), const Right<Failure, bool>(false));
      expect(historial.filas, hasLength(1));
    });

    test('un aviso sin id o sin título no se guarda: la pantalla no sabría mostrarlo', () async {
      final sinId = await registrar(aviso(' '));
      final sinTitulo = await registrar(aviso('b', titulo: '  '));

      expect(sinId.isLeft(), isTrue);
      expect(sinTitulo.isLeft(), isTrue);
      sinId.fold((f) => expect(f, isA<FailureValidacion>()), (_) {});
      expect(historial.filas, isEmpty);
    });
  });

  group('ResolverDestinoNotificacionUseCase', () {
    late DestinosEnMemoria destinos;
    late ResolverDestinoNotificacionUseCase resolver;
    setUp(() {
      destinos = DestinosEnMemoria();
      resolver = ResolverDestinoNotificacionUseCase(destinos);
    });

    test('un aviso sin destino no consulta nada', () async {
      final r = await resolver(aviso('a', conDestino: false));

      expect(r.getOrElse(() => throw StateError('falló')), isA<SinDestino>());
      expect(destinos.consultados, isEmpty);
    });

    test('un destino que existe se puede abrir', () async {
      final r = await resolver(aviso('a'));

      expect(
        r.getOrElse(() => throw StateError('falló')),
        isA<DestinoDisponible>().having(
          (d) => d.destino,
          'destino',
          const DestinoAgenda('agenda-a'),
        ),
      );
    });

    test('un destino que ya no existe se dice', () async {
      destinos.inexistentes.add(const DestinoAgenda('agenda-a'));

      final r = await resolver(aviso('a'));

      expect(r.getOrElse(() => throw StateError('falló')), isA<DestinoYaNoExiste>());
    });

    test('si no se puede saber, devuelve la falla y nunca lanza', () async {
      destinos.falla = true;

      final r = await resolver(aviso('a'));

      expect(r.isLeft(), isTrue);
      r.fold((f) => expect(f, isA<FailureInesperado>()), (_) {});
    });
  });

  group('los demás casos de uso', () {
    test(
      'marcar leída, marcar todas, borrar y purgar llaman al repositorio con el reloj',
      () async {
        final historial = HistorialEnMemoria([aviso('a'), aviso('b')]);

        await MarcarNotificacionLeidaUseCase(historial, ahora: () => ahoraDelCentro)('a');
        expect(historial.filas.firstWhere((n) => n.id == 'a').leidaEn, ahoraDelCentro.toUtc());

        await MarcarTodasLeidasUseCase(historial, ahora: () => ahoraDelCentro)();
        expect(historial.filas.every((n) => n.leida), isTrue);

        await PurgarHistorialNotificacionesUseCase(historial, ahora: () => ahoraDelCentro)();

        final borrado = await BorrarTodasLasNotificacionesUseCase(historial)(hasta: ahoraDelCentro);
        expect(borrado, const Right<Failure, int>(2));
        expect(historial.borrados, [ahoraDelCentro]);
      },
    );
  });
}
