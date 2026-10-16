// HU-UBI-006 / vista 10: la espera de 8 s de «Conservar A y unir» sin widgets ni plugins. El reloj es
// el falso de `fake_async`: ningún test espera de verdad.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
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
    _pantalla = contenedor.listen(unionesPendientesProvider, (_, _) {});
  }

  final DuplicadosEnMemoria datos;
  late final ProviderContainer contenedor;
  late final ProviderSubscription<UnionesPendientesState> _pantalla;

  /// La colportora sale de «Posibles duplicados»: nadie escucha más al notificador (que es
  /// `autoDispose`) y se descarta; la app y el resto de los providers siguen vivos.
  void salirDeLaPantalla() => _pantalla.close();

  /// Las uniones que fallaron cuando la pantalla ya no estaba.
  List<FallaUnion> get fallidasAlSalir => contenedor.read(unionesFallidasFueraDePantallaProvider);

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

  group('Seguimiento #340 · M2: unir otro par no borra el aviso de la falla', () {
    _conReloj('dado el aviso rojo de la unión de A–B, cuando uno otro par, la falla se queda hasta '
        'que se reintente o se descarte', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();
      expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'));
      banco.datos.falloAlUnir = null;

      banco.notificador.unir(_union('ub-c', 'ub-d'));
      reloj.flushMicrotasks();
      expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'), reason: 'al pedir la otra unión');

      reloj.elapse(_ocho);
      reloj.flushMicrotasks();
      expect(banco.unidas, ['ub-a<-ub-b', 'ub-c<-ub-d']);
      expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'), reason: 'al cumplirse la otra');
    });

    _conReloj('dado el aviso rojo de A–B, cuando deshago la unión de otro par, la falla sigue', (
      banco,
      reloj,
    ) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-c', 'ub-d'));
      banco.notificador.deshacer();

      expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'));
    });

    _conReloj('dado el aviso rojo de A–B, cuando lo reintento, se va el aviso (corre ya)', (
      banco,
      reloj,
    ) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();
      banco.datos.falloAlUnir = null;
      banco.notificador.unir(_union('ub-c', 'ub-d'));

      banco.notificador.reintentar();

      expect(banco.estado.falla, isNull);
      reloj.flushMicrotasks();
      expect(banco.unidas, ['ub-a<-ub-b', 'ub-a<-ub-b']);
    });

    _conReloj('dado el aviso rojo de A–B, cuando lo descarto con otra unión en espera, se va y la '
        'otra sigue esperando', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();
      banco.notificador.unir(_union('ub-c', 'ub-d'));

      banco.notificador.descartarFalla();

      expect(banco.estado.falla, isNull);
      expect(banco.estado.pendiente, _union('ub-c', 'ub-d'));
    });

    _conReloj(
      'dado el aviso rojo de A–B, cuando vuelvo a unir el MISMO par (en cualquier sentido), '
      'es otro intento y el aviso viejo se va',
      (banco, reloj) {
        banco.datos.falloAlUnir = const FailureInesperado();
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(_ocho);
        reloj.flushMicrotasks();
        expect(banco.estado.falla, isNotNull);

        banco.notificador.unir(_union('ub-b', 'ub-a'));

        expect(banco.estado.falla, isNull);
        expect(banco.estado.pendiente, _union('ub-b', 'ub-a'));
      },
    );

    _conReloj('dado el aviso rojo de A←B, cuando uno otro par con la misma duplicada B, la falla '
        'vieja se va: reintentarla chocaría con la nueva', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-c', 'ub-b'));

      expect(banco.estado.falla, isNull);
      expect(banco.estado.pendiente, _union('ub-c', 'ub-b'));
    });

    _conReloj('dado el aviso rojo de A←B, cuando uno otro par que CONSERVA a B, la falla vieja se '
        'va por lo mismo', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-b', 'ub-c'));

      expect(banco.estado.falla, isNull);
    });

    _conReloj('dado el aviso rojo de A←B, cuando uno otro par que conserva a A, la falla sigue: no '
        'chocan', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-a', 'ub-c'));

      expect(banco.estado.falla?.union, _union('ub-a', 'ub-b'));
    });

    _conReloj('dado el aviso rojo de A–B, cuando otra unión también falla, el aviso nuevo '
        'reemplaza al viejo y los dos pares vuelven a la lista', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.unir(_union('ub-c', 'ub-d'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      expect(banco.estado.falla?.union, _union('ub-c', 'ub-d'));
      expect(banco.estado.ocultas, isEmpty);
      expect(banco.estado.duplicadasEnCurso, isEmpty);
    });
  });

  group('Seguimiento #340 · M3: los pares con la duplicada pendiente se esconden', () {
    ParDuplicado par(String a, String b) => ParDuplicado(
      a: ubicacionDuplicable(a),
      b: ubicacionDuplicable(b),
      motivo: MotivoDuplicado.mismaDireccion,
      distanciaMetros: 3,
      admiteConservarAmbos: true,
    );

    _conReloj('dado A←B esperando, los pares que contienen a B (B–C) y el propio A–B se esconden; '
        'A–C no', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      expect(banco.estado.duplicadasEnCurso, {'ub-b'});
      expect(banco.estado.oculta(par('ub-a', 'ub-b')), isTrue);
      expect(banco.estado.oculta(par('ub-b', 'ub-c')), isTrue);
      expect(banco.estado.oculta(par('ub-c', 'ub-b')), isTrue, reason: 'B en cualquier lugar');
      expect(banco.estado.oculta(par('ub-a', 'ub-c')), isFalse, reason: 'A se queda');
      expect(banco.estado.oculta(par('ub-c', 'ub-d')), isFalse);
    });

    _conReloj('dado A←B esperando, cuando toco "Deshacer", B–C vuelve a la lista', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      banco.notificador.deshacer();

      expect(banco.estado.duplicadasEnCurso, isEmpty);
      expect(banco.estado.oculta(par('ub-b', 'ub-c')), isFalse);
    });

    _conReloj('dado A←B ya hecha, B–C sigue escondido mientras la base lo saca', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      expect(banco.unidas, ['ub-a<-ub-b']);
      expect(banco.estado.duplicadasEnCurso, {'ub-b'});
      expect(banco.estado.oculta(par('ub-b', 'ub-c')), isTrue);
    });

    _conReloj('dado A←B que falla, B–C vuelve a la lista junto con A–B', (banco, reloj) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      expect(banco.estado.duplicadasEnCurso, isEmpty);
      expect(banco.estado.oculta(par('ub-b', 'ub-c')), isFalse);
      expect(banco.estado.oculta(par('ub-a', 'ub-b')), isFalse);
    });

    _conReloj('dado A←B que falló, cuando la reintento, B–C se esconde de nuevo mientras corre', (
      banco,
      reloj,
    ) {
      banco.datos.falloAlUnir = const FailureInesperado();
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      reloj.elapse(_ocho);
      reloj.flushMicrotasks();

      banco.notificador.reintentar();

      expect(banco.estado.duplicadasEnCurso, {'ub-b'});
      expect(banco.estado.oculta(par('ub-b', 'ub-c')), isTrue);
    });

    _conReloj('dado A←B esperando y otro par C←D, cuando uno el segundo, las dos duplicadas se '
        'esconden y "Deshacer" solo suelta la última', (banco, reloj) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      banco.notificador.unir(_union('ub-c', 'ub-d'));

      expect(banco.estado.duplicadasEnCurso, {'ub-b', 'ub-d'});

      banco.notificador.deshacer();

      expect(banco.estado.duplicadasEnCurso, {'ub-b'});
    });

    _conReloj('dado que toco dos veces el mismo par, la duplicada se anota una sola vez', (
      banco,
      reloj,
    ) {
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      expect(banco.estado.duplicadasEnCurso, {'ub-b'});
    });
  });

  group('Seguimiento #340 · QA F3: la unión falla después de salir de la pantalla', () {
    // `autoDispose` descarta al notificador por el planificador de Riverpod, que no pasa por el reloj
    // falso: estos tests esperan de verdad el vaciado de la cola de eventos (la espera de 8 s no
    // corre, porque salir la hace definitiva en el acto).
    _Banco bancoAbierto() {
      final banco = _Banco();
      addTearDown(banco.cerrar);
      return banco;
    }

    test(
      'dado un par esperando, cuando salgo y la unión falla, la falla queda para la Lista',
      () async {
        final banco = bancoAbierto();
        banco.datos.falloAlUnir = const FailureInesperado();
        banco.notificador.unir(_union('ub-a', 'ub-b'));

        banco.salirDeLaPantalla();
        await pumpEventQueue();

        expect(banco.datos.uniones, hasLength(1), reason: 'al salir la unión se hizo definitiva');
        expect(banco.fallidasAlSalir, [
          FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado()),
        ]);
      },
    );

    test('dado un par esperando, cuando salgo y la unión anda, no queda nada que avisar', () async {
      final banco = bancoAbierto();
      banco.notificador.unir(_union('ub-a', 'ub-b'));

      banco.salirDeLaPantalla();
      await pumpEventQueue();

      expect(banco.unidas, ['ub-a<-ub-b']);
      expect(banco.fallidasAlSalir, isEmpty);
    });

    test(
      'dado que el puerto lanza al unir y salí, es una falla más: se avisa y nada revienta',
      () async {
        final banco = bancoAbierto();
        banco.datos.lanzaAlUnir = StateError('disco');
        banco.notificador.unir(_union('ub-a', 'ub-b'));

        banco.salirDeLaPantalla();
        await pumpEventQueue();

        expect(banco.fallidasAlSalir.single.falla, isA<FailureInesperado>());
      },
    );

    test('dado que la falla llega con la pantalla abierta, queda en la pantalla y no va a la '
        'Lista', () {
      fakeAsync((reloj) {
        final banco = _Banco();
        banco.datos.falloAlUnir = const FailureInesperado();
        banco.notificador.unir(_union('ub-a', 'ub-b'));
        reloj.elapse(_ocho);
        reloj.flushMicrotasks();

        expect(banco.estado.falla, isNotNull);
        expect(banco.fallidasAlSalir, isEmpty);
        banco.cerrar();
        reloj.flushMicrotasks();
      });
    });

    test('dado que salí con la primera unión todavía corriendo, las dos corren de a una y las dos '
        'fallas se avisan', () async {
      final banco = bancoAbierto();
      final espera = Completer<void>();
      banco.datos.retenerUniones = espera;
      banco.notificador.unir(_union('ub-a', 'ub-b'));
      banco.notificador.unir(_union('ub-c', 'ub-d')); // la primera se confirma ya
      await pumpEventQueue();

      banco.salirDeLaPantalla(); // la segunda también se confirma al salir
      await pumpEventQueue();
      banco.datos.falloAlUnir = const FailureInesperado();
      espera.complete();
      await pumpEventQueue();

      expect(banco.datos.uniones, hasLength(2), reason: 'las dos corrieron, de a una');
      expect(banco.fallidasAlSalir.map((f) => f.union.clavePar), ['ub-a|ub-b', 'ub-c|ub-d']);
    });

    test('dado que el mismo par falla dos veces fuera de la pantalla, queda una sola falla, la '
        'última', () {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      final almacen = contenedor.read(unionesFallidasFueraDePantallaProvider.notifier);

      almacen.registrar(
        FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado()),
      );
      almacen.registrar(
        FallaUnion(union: _union('ub-c', 'ub-d'), falla: const FailureInesperado()),
      );
      almacen.registrar(
        FallaUnion(union: _union('ub-b', 'ub-a'), falla: const FailureConservadaDeBaja()),
      );

      final fallidas = contenedor.read(unionesFallidasFueraDePantallaProvider);
      expect(fallidas.map((f) => f.union), [_union('ub-c', 'ub-d'), _union('ub-b', 'ub-a')]);
    });

    test('dado que se tocó "Revisar", cuando se olvidan las fallas, la lista queda vacía; y si ya '
        'estaba vacía no cambia nada', () {
      final contenedor = ProviderContainer();
      addTearDown(contenedor.dispose);
      var cambios = 0;
      contenedor.listen(unionesFallidasFueraDePantallaProvider, (_, _) => cambios++);
      final almacen = contenedor.read(unionesFallidasFueraDePantallaProvider.notifier);

      almacen.olvidar();
      expect(cambios, 0);

      almacen.registrar(
        FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado()),
      );
      almacen.olvidar();
      almacen.olvidar();

      expect(contenedor.read(unionesFallidasFueraDePantallaProvider), isEmpty);
      expect(cambios, 2);
    });

    test('dado que la app se cerró, cuando llega una falla tardía, no se rompe nada', () {
      final contenedor = ProviderContainer();
      final almacen = contenedor.read(unionesFallidasFueraDePantallaProvider.notifier);
      contenedor.dispose();

      expect(() {
        almacen.registrar(
          FallaUnion(union: _union('ub-a', 'ub-b'), falla: const FailureInesperado()),
        );
        almacen.olvidar();
      }, returnsNormally);
    });
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
      expect(
        const UnionesPendientesState(),
        isNot(const UnionesPendientesState(duplicadasEnCurso: {'x'})),
      );
    });
  });
}
