// HU-UBI-006 / vista 10: la espera de 8 s de «Conservar A y unir» sin widgets ni plugins. El reloj es
// el falso de `fake_async`: ningún test espera de verdad.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/duplicados_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/uniones_pendientes_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/duplicados_falsos.dart';

const _ocho = Duration(seconds: 8);

UnionPendiente _union(String conserva, String duplicada) => UnionPendiente(
  clavePar: conserva.compareTo(duplicada) <= 0 ? '$conserva|$duplicada' : '$duplicada|$conserva',
  conservarId: conserva,
  duplicadaId: duplicada,
  direccion: 'Av. Italia 1234',
);

final class _Banco {
  _Banco()
    : datos = DuplicadosEnMemoria(
        ubicaciones: [
          for (final (i, id) in ['ub-a', 'ub-b', 'ub-c', 'ub-d'].indexed)
            ubicacionDuplicable(id, metrosAlNorte: i * 1000),
        ],
      ) {
    contenedor = ProviderContainer(overrides: overridesDuplicados(datos));
    contenedor.listen(unionesPendientesProvider, (_, _) {});
  }

  final DuplicadosEnMemoria datos;
  late final ProviderContainer contenedor;

  UnionesPendientesState get estado => contenedor.read(unionesPendientesProvider);
  UnionesPendientesNotifier get notificador => contenedor.read(unionesPendientesProvider.notifier);

  List<String> get unidas => [for (final u in datos.uniones) '${u.conservadaId}<-${u.duplicadaId}'];

  void cerrar() {
    contenedor.dispose();
    unawaited(datos.cerrar());
  }
}

/// Corre [cuerpo] con un banco nuevo y el reloj falso.
void _conReloj(String descripcion, void Function(_Banco banco, FakeAsync reloj) cuerpo) {
  test(descripcion, () {
    fakeAsync((reloj) {
      final banco = _Banco();
      cuerpo(banco, reloj);
      banco.cerrar();
      reloj.flushMicrotasks();
    });
  });
}

void main() {
  test('el plazo de «Deshacer» es de 8 segundos', () {
    final contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);

    expect(contenedor.read(plazoDeshacerUnionProvider), _ocho);
  });

  group('Escenario: Conservar A y unir con 8 s de Deshacer', () {
    _conReloj('dado un par, cuando toco "Conservar A y unir", durante los 8 s no cambia nada en la '
        'base ni en la cola y el par queda escondido de la lista', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      reloj.elapse(_ocho - const Duration(milliseconds: 1));
      reloj.flushMicrotasks();

      expect(banco.estado.pendiente, _union('ub-a', 'ub-b'));
      expect(banco.estado.ocultas, {'ub-a|ub-b'});
      expect(banco.datos.uniones, isEmpty);
    });

    _conReloj('dado que pasaron los 8 s, cuando se cumple el plazo, la unión es definitiva y se '
        'hace una sola vez', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      reloj.elapse(_ocho);
      reloj.flushMicrotasks();
      reloj.elapse(const Duration(minutes: 1));
      reloj.flushMicrotasks();

      expect(banco.unidas, ['ub-a<-ub-b']);
      expect(banco.estado.pendiente, isNull);
      expect(banco.estado.ocultas, {'ub-a|ub-b'}, reason: 'no reaparece mientras la base lo saca');
      expect(banco.estado.falla, isNull);
    });

    _conReloj('dado el aviso con "Deshacer", cuando toco "Deshacer" dentro de los 8 s, no se une '
        'nada y el par vuelve a la lista', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(const Duration(seconds: 5));

      banco.notificador.deshacer();
      reloj.elapse(const Duration(minutes: 1));
      reloj.flushMicrotasks();

      expect(banco.estado.pendiente, isNull);
      expect(banco.estado.ocultas, isEmpty);
      expect(banco.datos.uniones, isEmpty);
    });

    _conReloj(
      'dado un par ya deshecho, cuando vuelvo a tocar "Conservar A y unir", arranca otros 8 s '
      'completos',
      (banco, reloj) {
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(const Duration(seconds: 6));
        banco.notificador.deshacer();

        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(const Duration(seconds: 7));
        reloj.flushMicrotasks();

        expect(banco.datos.uniones, isEmpty, reason: 'los 6 s anteriores no cuentan');

        reloj.elapse(const Duration(seconds: 1));
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b']);
      },
    );

    _conReloj('dado que "Deshacer" llega tarde (ya se unió), cuando lo toco, no pasa nada: no hay '
        'nada que deshacer', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.deshacer();
      reloj.flushMicrotasks();

      expect(banco.unidas, ['ub-a<-ub-b']);
      expect(banco.estado.ocultas, {'ub-a|ub-b'});
    });

    _conReloj(
      'dado que toco dos veces el mismo par, cuando pasa el segundo toque, no hace nada y no '
      'reinicia el tiempo',
      (banco, reloj) {
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(const Duration(seconds: 5));

        banco.notificador.unir(_union('ub-a', 'ub-b'));
        banco.notificador.unir(_union('ub-b', 'ub-a'));
        reloj.elapse(const Duration(seconds: 3));
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b'], reason: 'a los 8 s del primer toque, una sola unión');
      },
    );

    _conReloj('dado un par que ya se unió, cuando lo toco de nuevo, no se vuelve a unir', (
      banco,
      reloj,
    ) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      expect(banco.unidas, hasLength(1));
      expect(banco.estado.pendiente, isNull);
    });

    _conReloj('dado un par esperando, cuando uno otro par, el primero se hace definitivo en ese '
        'momento y los 8 s corren para el nuevo', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(const Duration(seconds: 3));

      banco.notificador.unir(_union('ub-c', 'ub-d'));
      reloj.flushMicrotasks();

      expect(banco.unidas, ['ub-a<-ub-b'], reason: 'la primera ya es definitiva');
      expect(banco.estado.pendiente, _union('ub-c', 'ub-d'));
      expect(banco.estado.ocultas, {'ub-a|ub-b', 'ub-c|ub-d'});

      reloj.elapse(const Duration(seconds: 7));
      reloj.flushMicrotasks();
      expect(banco.unidas, hasLength(1), reason: 'al nuevo le quedan 1 s');

      reloj.elapse(const Duration(seconds: 1));
      reloj.flushMicrotasks();
      expect(banco.unidas, ['ub-a<-ub-b', 'ub-c<-ub-d']);
    });

    _conReloj('dado otro par unido, cuando toco "Deshacer", deshago solo el último: el anterior ya '
        'es definitivo', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      banco.notificador.unir(_union('ub-c', 'ub-d'));

      banco.notificador.deshacer();
      reloj.elapse(const Duration(minutes: 1));
      reloj.flushMicrotasks();

      expect(banco.unidas, ['ub-a<-ub-b']);
      expect(banco.estado.ocultas, {'ub-a|ub-b'});
    });

    test('dado un par esperando, cuando el colportor sale de la pantalla (se descarta el '
        'notificador), la unión se hace definitiva', () {
      fakeAsync((reloj) {
        final banco = _Banco();
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(const Duration(seconds: 2));
        expect(banco.datos.uniones, isEmpty);

        banco.contenedor.dispose();
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b']);
        reloj.elapse(const Duration(minutes: 1));
        reloj.flushMicrotasks();
        expect(banco.unidas, hasLength(1), reason: 'el reloj cancelado no la repite');
        unawaited(banco.datos.cerrar());
      });
    });

    test('dado un par esperando, cuando la app se cierra de golpe (nadie descarta nada), no se '
        'hizo nada', () {
      fakeAsync((reloj) {
        final banco = _Banco();
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(const Duration(seconds: 7));
        reloj.flushMicrotasks();

        // El proceso muere acá: no hay dispose ni cierre.
        expect(banco.datos.uniones, isEmpty);
        banco.cerrar();
        reloj.flushMicrotasks();
      });
    });
  });

  group('Escenario: la unión falla', () {
    _conReloj(
      'dado que la base falla al unir, cuando se cumplen los 8 s, el par vuelve a la lista, '
      'el botón se puede volver a tocar y queda la falla para avisar',
      (banco, reloj) {
        banco.datos.falloAlUnir = const FailureInesperado();
        banco.notificador.unir(_union('ub-a', 'ub-b'));

        reloj.elapse(_ocho);
        reloj.flushMicrotasks();

        expect(banco.estado.pendiente, isNull);
        expect(banco.estado.ocultas, isEmpty, reason: 'ningún estado de ocupado queda trabado');
        expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'));
        expect(banco.estado.falla?.falla, const FailureInesperado());
        expect(banco.estado.falla?.sePuedeReintentar, isTrue);

        banco.datos.falloAlUnir = null;
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        expect(banco.estado.pendiente, isNotNull, reason: 'se puede volver a pedir');
      },
    );

    _conReloj(
      'dado que el puerto lanza una excepción, cuando se cumplen los 8 s, no se rompe nada: '
      'es una falla más',
      (banco, reloj) {
        banco.datos.lanzaAlUnir = StateError('disco');
        banco.notificador.unir(_union('ub-a', 'ub-b'));

        reloj.elapse(_ocho);
        reloj.flushMicrotasks();

        expect(banco.estado.falla?.falla, isA<FailureInesperado>());
        expect(banco.estado.ocultas, isEmpty);
      },
    );

    _conReloj(
      'dado una falla, cuando toco "Reintentar", la unión corre ya sin otra espera de 8 s y, '
      'si anda, no queda falla',
      (banco, reloj) {
        banco.datos.falloAlUnir = const FailureInesperado();
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(_ocho);
        reloj.flushMicrotasks();
        banco.datos.falloAlUnir = null;

        banco.notificador.reintentar();
        expect(banco.estado.falla, isNull);
        expect(banco.estado.ocultas, {'ub-a|ub-b'});
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b', 'ub-a<-ub-b']);
        expect(banco.estado.falla, isNull);
        expect(banco.estado.ocultas, {'ub-a|ub-b'});
      },
    );

    _conReloj('dado una falla que se repite, cuando toco "Reintentar" y vuelve a fallar, la falla '
        'sigue y el par vuelve a la lista', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.reintentar();
      reloj.flushMicrotasks();

      expect(banco.datos.uniones, hasLength(2));
      expect(banco.estado.falla, isNotNull);
      expect(banco.estado.ocultas, isEmpty);
    });

    _conReloj('dado que la que se conserva ya está de baja, cuando se cumplen los 8 s, no se puede '
        'reintentar (hay que revisar el par) y "Reintentar" no hace nada', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureConservadaDeBaja();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      expect(banco.estado.falla?.sePuedeReintentar, isFalse);

      banco.notificador.reintentar();
      reloj.flushMicrotasks();

      expect(banco.datos.uniones, hasLength(1));
      expect(banco.estado.falla?.falla, const FailureConservadaDeBaja());
    });

    _conReloj('dado una falla, cuando la descarto, el aviso se va y el estado queda limpio', (
      banco,
      reloj,
    ) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.descartarFalla();
      banco.notificador.descartarFalla();

      expect(banco.estado.falla, isNull);
      expect(banco.estado, const UnionesPendientesState());
    });

    _conReloj('dado que no hay falla, cuando toco "Reintentar", no hace nada', (banco, reloj) {
      banco.notificador.reintentar();
      reloj.flushMicrotasks();

      expect(banco.datos.uniones, isEmpty);
    });

    test('dado un par esperando que va a fallar, cuando se sale de la pantalla, la falla no '
        'revienta a nadie (el repositorio ya dejó el log)', () {
      fakeAsync((reloj) {
        final banco = _Banco();
        banco.datos.lanzaAlUnir = StateError('disco');
        banco.notificador.unir(_union('ub-a', 'ub-b'));

        banco.contenedor.dispose();
        reloj.flushMicrotasks();

        expect(banco.datos.uniones, hasLength(1));
        unawaited(banco.datos.cerrar());
      });
    });
  });

  group('Escenario: dos acciones seguidas antes de que termine la primera', () {
    test('dado que la primera unión todavía no terminó, cuando se cumple la segunda, corren de a '
        'una y en el orden en que se pidieron', () {
      fakeAsync((reloj) {
        final banco = _Banco();
        final espera = Completer<void>();
        banco.datos.retenerUniones = espera;

        banco.notificador.unir(_union('ub-a', 'ub-b'));
        banco.notificador.unir(_union('ub-c', 'ub-d')); // la primera se confirma ya
        reloj.elapse(_ocho); // la segunda también
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b'], reason: 'la segunda espera a que termine la primera');

        espera.complete();
        reloj.flushMicrotasks();

        expect(banco.unidas, ['ub-a<-ub-b', 'ub-c<-ub-d']);
        banco.cerrar();
        reloj.flushMicrotasks();
      });
    });

    test(
      'dado que la primera falla mientras la segunda espera su Deshacer, cuando termina, la falla '
      'aparece sin pisar el aviso de la segunda',
      () {
        fakeAsync((reloj) {
          final banco = _Banco();
          banco.datos.falloAlUnir = const FailureInesperado();

          banco.notificador.unir(_union('ub-a', 'ub-b'));
          banco.notificador.unir(_union('ub-c', 'ub-d'));
          reloj.flushMicrotasks();

          expect(banco.estado.pendiente, _union('ub-c', 'ub-d'));
          expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'));
          expect(banco.estado.ocultas, {'ub-c|ub-d'}, reason: 'el par que falló vuelve a la lista');

          banco.notificador.deshacer();
          expect(banco.estado.pendiente, isNull);
          expect(banco.estado.falla, isNotNull, reason: 'deshacer no borra la falla de la otra');
          banco.cerrar();
          reloj.flushMicrotasks();
        });
      },
    );
  });

  group('Igualdad por valor (Equatable)', () {
    test('dado dos instancias con los mismos datos, son iguales; con otro dato, distintas', () {
      final falla = FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado());

      expect(_union('ub-a', 'ub-b'), _union('ub-a', 'ub-b'));
      expect(_union('ub-a', 'ub-b'), isNot(_union('ub-b', 'ub-a')));
      expect(falla, FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado()));
      expect(
        falla,
        isNot(FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureConservadaDeBaja())),
      );
      expect(const UnionesPendientesState(), const UnionesPendientesState());
      expect(const UnionesPendientesState(), isNot(const UnionesPendientesState(ocultas: {'x'})));
    });
  });
}
