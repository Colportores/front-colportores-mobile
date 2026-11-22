// HU-CTA-002 (#441) — la deuda con la casa editora: el RPC `mi_deuda_con_la_casa_editora` (backend-supabase
// 0164) se traduce a la entidad, se guarda con su hora en la DB cifrada y se lee sin conexión. Importa
// supabase_flutter y Drift (que arrastran Flutter), así que usa flutter_test y no `test`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/deuda_con_la_casa_cache_data_source.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/deuda_con_la_casa_remote_data_source.dart';
import 'package:colportores_mobile/features/cuenta/data/models/deuda_con_la_casa_model.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/deuda_con_la_casa_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:dartz/dartz.dart' show Left;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../helpers/logger_mudo.dart';

/// Lo que contesta el RPC para el canvas 33B·01: $ 18.400 en dos pedidos (montos en centavos).
Map<String, Object?> _respuestaDelCanvas() => {
  'deuda_total': 1840000,
  'suma_de_saldos': 1840000,
  'depositos_validados': 2380000,
  'pedidos': [
    {
      'pedido_id': 'p-1',
      'numero': 7,
      'fecha_pedido': '2026-10-02T15:00:00+00:00',
      'estado': 'RECIBIDO',
      'monto': 3740000,
      'pagado': 2200000,
      'saldo': 1540000,
      'lineas': [
        {'producto_id': 'a', 'nombre': 'Salud y Hogar', 'cantidad': 10},
        {'producto_id': 'b', 'nombre': 'Nuestros Hijos', 'cantidad': 6},
      ],
    },
    {
      'pedido_id': 'p-2',
      'numero': 9,
      'fecha_pedido': '2026-10-15T15:00:00+00:00',
      'estado': 'AUTORIZADO',
      'monto': 480000,
      'pagado': 180000,
      'saldo': 300000,
      'lineas': [
        {'producto_id': 'c', 'nombre': 'Vida Feliz', 'cantidad': 40},
      ],
    },
  ],
};

/// Un remoto que el test maneja.
final class _Remoto implements DeudaConLaCasaRemoteDataSource {
  _Remoto(this.respuesta);

  Future<Object?> Function() respuesta;
  var llamadas = 0;

  @override
  Future<Object?> leer() {
    llamadas++;
    return respuesta();
  }
}

/// Un cache en memoria que el test puede romper.
final class _Cache implements DeudaConLaCasaCacheDataSource {
  DeudaGuardada? guardado;
  var falla = false;
  var guardados = 0;

  @override
  Future<DeudaGuardada?> leer(String colportorId) async {
    if (falla) throw StateError('base ilegible');
    return guardado;
  }

  @override
  Future<void> guardar(String colportorId, String respuesta, DateTime leidaEn) async {
    if (falla) throw StateError('base ilegible');
    guardados++;
    guardado = (respuesta: respuesta, leidaEn: leidaEn);
  }
}

final _ahora = DateTime.utc(2026, 11, 4, 13);

DeudaConLaCasaRepositoryImpl _repo(_Remoto remoto, DeudaConLaCasaCacheDataSource cache) =>
    DeudaConLaCasaRepositoryImpl(remoto, cache, ahora: () => _ahora, logger: loggerMudo());

void main() {
  group('El modelo: del JSON del RPC a la entidad', () {
    test(
      'dado el JSON del canvas 33B·01, cuando se lee, salen el total y cada pedido en centavos',
      () {
        final deuda = DeudaConLaCasaModel.desdeJson(_respuestaDelCanvas());

        expect(deuda.deudaTotalCentavos, 1840000);
        expect(deuda.sumaDeSaldosCentavos, 1840000);
        expect(deuda.depositosValidadosCentavos, 2380000);
        expect(deuda.pedidos, hasLength(2));
        final primero = deuda.pedidos.first;
        expect(primero.pedidoId, 'p-1');
        expect(primero.fechaPedido, DateTime.utc(2026, 10, 2, 15));
        expect(primero.montoCentavos, 3740000);
        expect(primero.pagadoCentavos, 2200000);
        expect(primero.saldoCentavos, 1540000);
        expect(primero.lineas.map((l) => (l.nombre, l.cantidad)), [
          ('Salud y Hogar', 10),
          ('Nuestros Hijos', 6),
        ]);
        expect(deuda.saldosNoDanElTotal, isFalse);
        expect(deuda.sinDeuda, isFalse);
      },
    );

    test(
      'un monto que llega como número con decimales en cero se entiende; uno con fracción, no',
      () {
        final ok = _respuestaDelCanvas()..['deuda_total'] = 1840000.0;
        expect(DeudaConLaCasaModel.desdeJson(ok).deudaTotalCentavos, 1840000);

        final mal = _respuestaDelCanvas()..['deuda_total'] = 18400.5;
        expect(() => DeudaConLaCasaModel.desdeJson(mal), throwsFormatException);
      },
    );

    test('una respuesta incompleta o con otro tipo no se adivina: lanza FormatException', () {
      for (final mala in <Object?>[
        null,
        'ACTIVA',
        <Object?>[],
        <String, Object?>{},
        {..._respuestaDelCanvas()}..remove('deuda_total'),
        {..._respuestaDelCanvas()}..['pedidos'] = 'x',
        {..._respuestaDelCanvas()}..['pedidos'] = [5],
        {..._respuestaDelCanvas()}..['suma_de_saldos'] = '0',
        {
          ..._respuestaDelCanvas(),
          'pedidos': [
            {'pedido_id': 'p-1'},
          ],
        },
        {
          ..._respuestaDelCanvas(),
          'pedidos': [
            {
              ...(_respuestaDelCanvas()['pedidos']! as List).first as Map<String, Object?>,
              'fecha_pedido': 'ayer',
            },
          ],
        },
      ]) {
        expect(() => DeudaConLaCasaModel.desdeJson(mala), throwsFormatException, reason: '$mala');
      }
    });

    test('deuda_hace_7_dias (backend-supabase 0168): un entero, `null` o sin la clave', () {
      final con7 = _respuestaDelCanvas()..['deuda_hace_7_dias'] = 2050000;
      final deuda = DeudaConLaCasaModel.desdeJson(con7);
      expect(deuda.deudaHace7DiasCentavos, 2050000);
      expect(deuda.variacionCentavos, -210000);

      // Nada registrado hace 7 días: no es «igual», es «sin datos».
      final nula = _respuestaDelCanvas()..['deuda_hace_7_dias'] = null;
      expect(DeudaConLaCasaModel.desdeJson(nula).deudaHace7DiasCentavos, isNull);
      expect(DeudaConLaCasaModel.desdeJson(nula).variacionCentavos, isNull);

      // Una respuesta guardada antes de la migración no trae la clave.
      expect(DeudaConLaCasaModel.desdeJson(_respuestaDelCanvas()).deudaHace7DiasCentavos, isNull);

      // Estaba a favor hace 7 días (negativa): también es un entero válido.
      final aFavor = _respuestaDelCanvas()..['deuda_hace_7_dias'] = -50000;
      expect(DeudaConLaCasaModel.desdeJson(aFavor).variacionCentavos, 1890000);

      for (final mala in <Object?>['20500', 20500.5, true, <Object?>[]]) {
        final r = _respuestaDelCanvas()..['deuda_hace_7_dias'] = mala;
        expect(() => DeudaConLaCasaModel.desdeJson(r), throwsFormatException, reason: '$mala');
      }
    });

    test('un pedido sin líneas se lee con la lista vacía', () {
      final r = _respuestaDelCanvas();
      ((r['pedidos']! as List).first as Map<String, Object?>)['lineas'] = <Object?>[];

      expect(DeudaConLaCasaModel.desdeJson(r).pedidos.first.lineas, isEmpty);
    });
  });

  group('La entidad: qué dice cada caso', () {
    DeudaConLaCasa con({int total = 0, int suma = 0, int pedidos = 0}) => DeudaConLaCasa(
      deudaTotalCentavos: total,
      sumaDeSaldosCentavos: suma,
      depositosValidadosCentavos: 0,
      pedidos: [
        for (var i = 0; i < pedidos; i++)
          PedidoConSaldo(
            pedidoId: 'p-$i',
            fechaPedido: DateTime.utc(2026, 10, 1),
            montoCentavos: 100,
            pagadoCentavos: 0,
            saldoCentavos: 100,
            lineas: const [],
          ),
      ],
    );

    test(
      'la variación es la deuda de hoy menos la de hace 7 días, y sin la de hace 7 días no hay',
      () {
        DeudaConLaCasa de({int? hace7}) => DeudaConLaCasa(
          deudaTotalCentavos: 1840000,
          sumaDeSaldosCentavos: 1840000,
          depositosValidadosCentavos: 0,
          pedidos: const [],
          deudaHace7DiasCentavos: hace7,
        );

        expect(de(hace7: 2050000).variacionCentavos, -210000);
        expect(de(hace7: 1500000).variacionCentavos, 340000);
        expect(de(hace7: 1840000).variacionCentavos, 0);
        expect(de().variacionCentavos, isNull);
        // La deuda de hace 7 días cuenta en la igualdad.
        expect(de(hace7: 1), isNot(equals(de(hace7: 2))));
        expect(de(hace7: 1), equals(de(hace7: 1)));
      },
    );

    test('sin deuda: cero y ningún pedido', () {
      expect(con().sinDeuda, isTrue);
      expect(con().saldosNoDanElTotal, isFalse);
      expect(con(total: 100, pedidos: 1, suma: 100).sinDeuda, isFalse);
    });

    test('con deuda real y ningún pedido que la explique, no es «sin deuda» y se aclara', () {
      final d = con(total: 500);
      expect(d.sinDeuda, isFalse);
      expect(d.saldosNoDanElTotal, isTrue);
    });

    test('en cero pero con pedidos con saldo, no es «sin deuda» y se aclara', () {
      final d = con(suma: 100, pedidos: 1);
      expect(d.sinDeuda, isFalse);
      expect(d.saldosNoDanElTotal, isTrue);
    });

    test('quedar a favor sin saldos ya se explica solo; con saldos que no cuadran, se aclara', () {
      expect(con(total: -500).aFavor, isTrue);
      expect(con(total: -500).saldosNoDanElTotal, isFalse);
      expect(con(total: -500, suma: 100, pedidos: 1).saldosNoDanElTotal, isTrue);
    });
  });

  group('El repositorio: pregunta al servidor y se acuerda de lo último', () {
    test('dado un servidor que contesta, cuando lee, devuelve la deuda con la hora de ahora y la '
        'guarda tal cual vino', () async {
      final cache = _Cache();
      final repo = _repo(_Remoto(() async => _respuestaDelCanvas()), cache);

      final resultado = await repo.leer('col-1');

      final lectura = resultado.getOrElse(() => throw StateError('debía ser Right'));
      expect(lectura.deuda.deudaTotalCentavos, 1840000);
      expect(lectura.leidaEn, _ahora);
      expect(cache.guardados, 1);
      expect(jsonDecode(cache.guardado!.respuesta), _respuestaDelCanvas());
      expect(cache.guardado!.leidaEn, _ahora);
    });

    test('lo guardado se lee después igual que lo que llegó, con su hora', () async {
      final cache = _Cache();
      final repo = _repo(_Remoto(() async => _respuestaDelCanvas()), cache);
      final fresca = (await repo.leer('col-1')).getOrElse(() => throw StateError('x'));

      final guardada = await repo.ultimaGuardada('col-1');

      expect(guardada, fresca);
    });

    test('sin nada guardado, la última guardada es null', () async {
      expect(await _repo(_Remoto(() async => null), _Cache()).ultimaGuardada('col-1'), isNull);
    });

    test('sin conexión devuelve FailureDeudaSinConexion y deja lo guardado como estaba', () async {
      final cache = _Cache()
        ..guardado = (respuesta: jsonEncode(_respuestaDelCanvas()), leidaEn: _ahora);
      final repo = _repo(
        _Remoto(() => Future<Object?>.error(const DeudaSinConexionException())),
        cache,
      );

      final resultado = await repo.leer('col-1');

      expect(resultado, const Left<Failure, LecturaDeLaDeuda>(FailureDeudaSinConexion()));
      expect(cache.guardados, 0);
      expect((await repo.ultimaGuardada('col-1'))!.deuda.deudaTotalCentavos, 1840000);
    });

    test('un error del servidor devuelve FailureDeudaNoDisponible y no toca lo guardado', () async {
      final cache = _Cache();
      final repo = _repo(
        _Remoto(() => Future<Object?>.error(const DeudaServidorException(codigo: '42501'))),
        cache,
      );

      expect(
        await repo.leer('col-1'),
        const Left<Failure, LecturaDeLaDeuda>(FailureDeudaNoDisponible()),
      );
      expect(cache.guardados, 0);
    });

    test(
      'una falla rara (no una DeudaRemotaException) tampoco se escapa: es no disponible',
      () async {
        final repo = _repo(_Remoto(() => Future<Object?>.error(StateError('x'))), _Cache());

        expect(
          await repo.leer('col-1'),
          const Left<Failure, LecturaDeLaDeuda>(FailureDeudaNoDisponible()),
        );
      },
    );

    test('una respuesta que no se entiende no se muestra ni se guarda', () async {
      final cache = _Cache();
      final repo = _repo(_Remoto(() async => {'deuda_total': 'mucho'}), cache);

      expect(
        await repo.leer('col-1'),
        const Left<Failure, LecturaDeLaDeuda>(FailureDeudaNoDisponible()),
      );
      expect(cache.guardados, 0);
    });

    test('si no se puede guardar, igual devuelve lo que acaba de llegar', () async {
      final cache = _Cache()..falla = true;
      final repo = _repo(_Remoto(() async => _respuestaDelCanvas()), cache);

      final resultado = await repo.leer('col-1');

      expect(resultado.isRight(), isTrue);
    });

    test('lo guardado que ya no se entiende, o una base ilegible, es como no tener nada', () async {
      final cache = _Cache()..guardado = (respuesta: '{"viejo": true}', leidaEn: _ahora);
      final repo = _repo(_Remoto(() async => null), cache);
      expect(await repo.ultimaGuardada('col-1'), isNull);

      cache.guardado = (respuesta: 'no es json', leidaEn: _ahora);
      expect(await repo.ultimaGuardada('col-1'), isNull);

      cache.falla = true;
      expect(await repo.ultimaGuardada('col-1'), isNull);
    });

    test('dos lecturas seguidas: la segunda pisa a la primera', () async {
      final cache = _Cache();
      var n = 0;
      final repo = _repo(
        _Remoto(() async => {..._respuestaDelCanvas(), 'deuda_total': 100 * ++n}),
        cache,
      );

      await repo.leer('col-1');
      await repo.leer('col-1');

      expect((await repo.ultimaGuardada('col-1'))!.deuda.deudaTotalCentavos, 200);
    });
  });

  group('La tabla deuda_casa_cache: una fila por colportor, en la DB', () {
    late AppDatabase db;
    late DeudaConLaCasaCacheDrift cache;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      cache = DeudaConLaCasaCacheDrift(db);
    });

    tearDown(() => db.close());

    test('nada guardado es null; guardar y leer devuelve el JSON y la hora', () async {
      expect(await cache.leer('col-1'), isNull);

      await cache.guardar('col-1', '{"a":1}', DateTime.utc(2026, 11, 3, 21));

      final guardado = await cache.leer('col-1');
      expect(guardado!.respuesta, '{"a":1}');
      expect(guardado.leidaEn, DateTime.utc(2026, 11, 3, 21));
    });

    test('guardar de nuevo pisa la fila del mismo colportor y no toca la de otro', () async {
      await cache.guardar('col-1', '{"a":1}', DateTime.utc(2026, 11, 3));
      await cache.guardar('col-2', '{"b":2}', DateTime.utc(2026, 11, 3));

      await cache.guardar('col-1', '{"a":3}', DateTime.utc(2026, 11, 4));

      expect((await cache.leer('col-1'))!.respuesta, '{"a":3}');
      expect((await cache.leer('col-1'))!.leidaEn, DateTime.utc(2026, 11, 4));
      expect((await cache.leer('col-2'))!.respuesta, '{"b":2}');
      expect(await db.select(db.deudaCasaCaches).get(), hasLength(2));
    });

    test(
      'el repositorio sobre la DB: lee del servidor, queda guardado y se ve sin conexión',
      () async {
        final conServidor = _repo(_Remoto(() async => _respuestaDelCanvas()), cache);
        await conServidor.leer('col-1');

        final sinConexion = _repo(
          _Remoto(() => Future<Object?>.error(const DeudaSinConexionException())),
          cache,
        );

        final guardada = await sinConexion.ultimaGuardada('col-1');
        expect(guardada!.deuda.pedidos, hasLength(2));
        expect(guardada.leidaEn, _ahora);
        expect(await sinConexion.ultimaGuardada('col-2'), isNull);
      },
    );

    test('la sin cache no guarda nada ni falla', () async {
      const sin = DeudaConLaCasaSinCache();
      await sin.guardar('col-1', '{}', _ahora);

      expect(await sin.leer('col-1'), isNull);
    });
  });

  group('El remoto: el RPC con la sesión de la app', () {
    DeudaConLaCasaSupabase fuente(Future<Object?> Function() rpc) =>
        DeudaConLaCasaSupabase(rpc, logger: loggerMudo());

    test('si el servidor no contesta a tiempo, es una falla de red y no queda esperando para '
        'siempre', () async {
      final nuncaContesta = Completer<Object?>();
      final fuenteLenta = DeudaConLaCasaSupabase(
        () => nuncaContesta.future,
        tope: const Duration(milliseconds: 20),
        logger: loggerMudo(),
      );

      await expectLater(fuenteLenta.leer(), throwsA(isA<DeudaSinConexionException>()));
    });

    test('con el repositorio, el servidor que no contesta es «sin conexión» y lo guardado '
        'sigue ahí', () async {
      final nuncaContesta = Completer<Object?>();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DeudaConLaCasaRepositoryImpl(
        DeudaConLaCasaSupabase(
          () => nuncaContesta.future,
          tope: const Duration(milliseconds: 20),
          logger: loggerMudo(),
        ),
        DeudaConLaCasaCacheDrift(db),
        ahora: () => DateTime.utc(2026, 11, 4, 13),
        logger: loggerMudo(),
      );

      final resultado = await repo.leer('col-1');

      expect(resultado.isLeft(), isTrue);
      resultado.fold(
        (falla) => expect(falla, isA<FailureDeudaSinConexion>()),
        (_) => fail('no debía haber lectura'),
      );
    });

    test('cuando el servidor contesta, devuelve el JSON tal cual', () async {
      expect(await fuente(() async => _respuestaDelCanvas()).leer(), _respuestaDelCanvas());
    });

    test('un error del servidor lleva su SQLSTATE; sin sesión es 42501', () async {
      await expectLater(
        fuente(
          () => Future<Object?>.error(
            const PostgrestException(message: 'Iniciá sesión…', code: '42501'),
          ),
        ).leer(),
        throwsA(isA<DeudaServidorException>().having((e) => e.codigo, 'codigo', '42501')),
      );
    });

    for (final (nombre, error) in <(String, Object)>[
      ('sin red (SocketException)', const SocketException('sin ruta')),
      ('corte a mitad (ClientException)', http.ClientException('cortado')),
      ('tiempo agotado (TimeoutException)', TimeoutException('lento')),
      ('la sesión no se pudo renovar por la red', AuthRetryableFetchException(message: 'sin red')),
    ]) {
      test('$nombre es «sin conexión»', () async {
        await expectLater(
          fuente(() => Future<Object?>.error(error)).leer(),
          throwsA(isA<DeudaSinConexionException>()),
        );
      });
    }

    test('una sesión rechazada es un error del servidor, no «sin conexión»', () async {
      await expectLater(
        fuente(() => Future<Object?>.error(const AuthException('vencida'))).leer(),
        throwsA(isA<DeudaServidorException>().having((e) => e.codigo, 'codigo', '42501')),
      );
    });

    test('sin Supabase configurado (tests, demo) se comporta como sin conexión', () async {
      await expectLater(
        const DeudaConLaCasaSinServidor().leer(),
        throwsA(isA<DeudaSinConexionException>()),
      );
    });
  });
}
