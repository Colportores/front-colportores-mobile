// QA de #419 (HU-CAT-006, precios en el teléfono; PR sin vista, sin artboards). Casos que el PR no
// cubre: la base real que falla (no un fake de `observar`), el Stream que se recupera, bajadas
// parciales o en ráfaga, ciudades hostiles, volumen y textos límite, reentrada y privacidad del log.
// Las filas entran por el mismo `DriftLocalStore` del motor, como las arma `sync.pull`.
import 'dart:async';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/catalogo/data/datasources/catalogo_local_data_source.dart';
import 'package:colportores_mobile/features/catalogo/data/repositories/consulta_de_precios_repository_impl.dart';
import 'package:colportores_mobile/features/catalogo/data/repositories/dias_de_antiguedad_de_precios_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/catalogo/domain/services/resolvedor_de_precios.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../helpers/logger_mudo.dart';

const _hoy = '2026-10-28';
const _rivera = 'cc-rivera';
const _montevideo = 'cc-montevideo';
const _fecha = '2026-10-20T12:00:00+00:00';

Map<String, Object?> _producto(String id, String nombre, {String? codigo, String tipo = 'LIBRO'}) =>
    {
      'id': id,
      'nombre': nombre,
      'descripcion': null,
      'tipo': tipo,
      'es_bonificable': false,
      'es_misionero': false,
      'precio_base_compra': null,
      'casa_editora': null,
      'imagen_url': null,
      'created_at': _fecha,
      'updated_at': _fecha,
      'created_by': null,
      'deleted_at': null,
      'sync_version': 1,
      'codigo_editor': codigo,
    };

Map<String, Object?> _excepcion(
  String id,
  String ciudad,
  int centavos, {
  String? producto,
  String? combo,
}) => {
  'id': id,
  'producto_id': producto,
  'coleccion_id': combo,
  'campania_ciudad_id': ciudad,
  'precio_venta': centavos,
  'valido_desde': '2026-01-01',
  'valido_hasta': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

Map<String, Object?> _general(String id, int centavos, {String? producto, String? combo}) => {
  'id': id,
  'producto_id': producto,
  'coleccion_id': combo,
  'precio_venta': centavos,
  'valido_desde': '2026-01-01',
  'valido_hasta': null,
  'created_at': _fecha,
  'updated_at': _fecha,
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

Map<String, Object?> _parametro(int valor, {String id = 'par-1', String actualizado = _fecha}) => {
  'id': id,
  'clave': 'dias_antiguedad_precios',
  'valor': valor,
  'created_at': _fecha,
  'updated_at': actualizado,
  'created_by': null,
  'deleted_at': null,
  'sync_version': 1,
};

/// Falla la primera lectura y después anda: una base que se traba un momento.
class _FallaUnaVez extends CatalogoLocalDataSource {
  _FallaUnaVez(super.db);
  int lecturas = 0;

  @override
  Future<CatalogoLocal> leer(String campaniaCiudadId) async {
    lecturas++;
    if (lecturas == 1) throw StateError('disco ocupado de Rosa Pérez 099123456');
    return super.leer(campaniaCiudadId);
  }
}

class _Captura extends LogOutput {
  final lineas = <String>[];
  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late DriftLocalStore store;
  late CatalogoLocalDataSource datos;
  var marca = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    store = DriftLocalStore(db, entidades: entidadesQueEscribeElMotor);
    datos = CatalogoLocalDataSource(db);
    marca = 0;
  });
  tearDown(() async {
    try {
      await db.close();
    } on Object {
      // ya cerrada por el test
    }
  });

  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas) =>
      store.applyDelta(filas, scope: 'replica', watermark: 'w${++marca}');

  Future<void> esperar(bool Function() condicion, {int ms = 3000}) async {
    for (var i = 0; i < ms ~/ 5 && !condicion(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  group('la base real falla (no un fake de observar)', () {
    test('una tabla dañada: observar termina en el aviso 26·10, sin catálogo vacío', () async {
      await db.customStatement('DROP TABLE precio_general');
      final repo = ConsultaDePreciosRepositoryImpl(
        CatalogoLocalDataSource(db),
        logger: loggerMudo(),
      );
      final eventos = <Object>[];
      final fin = Completer<void>();
      final sub = repo
          .observar(_rivera)
          .listen(
            eventos.add,
            onError: (Object e) {
              eventos.add(e);
              if (!fin.isCompleted) fin.complete();
            },
          );
      addTearDown(sub.cancel);

      await fin.future.timeout(const Duration(seconds: 5));

      expect(eventos.whereType<CatalogoLocal>(), isEmpty);
      expect(eventos.first, isA<FailurePreciosNoDisponibles>());
    });

    test(
      'una lectura que falla una vez no mata el Stream: el próximo cambio emite el catálogo',
      () async {
        final fuente = _FallaUnaVez(db);
        final repo = ConsultaDePreciosRepositoryImpl(fuente, logger: loggerMudo());
        final eventos = <Object>[];
        final sub = repo.observar(_rivera).listen(eventos.add, onError: eventos.add);
        addTearDown(sub.cancel);

        await esperar(() => eventos.isNotEmpty);
        expect(eventos.single, isA<FailurePreciosNoDisponibles>());

        await bajar({
          'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
          'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        });
        await esperar(() => eventos.whereType<CatalogoLocal>().isNotEmpty);

        final catalogo = eventos.whereType<CatalogoLocal>().last;
        expect(ResolvedorDePrecios.resolver(catalogo, dia: _hoy).map((i) => i.centavos), [45000]);
      },
    );
  });

  group('bajadas del pull', () {
    test(
      'un precio que llega antes que su producto no se ofrece ni rompe nada; cuando llega el producto aparece',
      () async {
        final emisiones = <CatalogoLocal>[];
        final sub = datos.observar(_rivera).listen(emisiones.add);
        addTearDown(sub.cancel);
        await esperar(() => emisiones.isNotEmpty);

        await bajar({
          'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        });
        await esperar(() => emisiones.length >= 2);
        expect(ResolvedorDePrecios.resolver(emisiones.last, dia: _hoy), isEmpty);

        await bajar({
          'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        });
        await esperar(() => emisiones.length >= 3);
        expect(ResolvedorDePrecios.resolver(emisiones.last, dia: _hoy).map((i) => i.centavos), [
          45000,
        ]);
      },
    );

    test(
      'una bajada con producto y precio juntos se ve entera: ninguna emisión tiene el precio sin su producto',
      () async {
        final emisiones = <CatalogoLocal>[];
        final sub = datos.observar(_rivera).listen(emisiones.add);
        addTearDown(sub.cancel);
        await esperar(() => emisiones.isNotEmpty);

        await bajar({
          'producto': [for (var i = 0; i < 30; i++) _producto('pro-$i', 'Libro $i')],
          'precio_general': [
            for (var i = 0; i < 30; i++) _general('pg-$i', 1000 + i, producto: 'pro-$i'),
          ],
          'precio_por_ciudad': [
            for (var i = 0; i < 30; i++) _excepcion('ppc-$i', _rivera, 900 + i, producto: 'pro-$i'),
          ],
        });
        await esperar(() => emisiones.length >= 2);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        for (final e in emisiones) {
          final ids = e.productos.map((p) => p.id).toSet();
          expect(e.generales.every((g) => ids.contains(g.productoId)), isTrue);
          expect(e.excepciones.every((g) => ids.contains(g.productoId)), isTrue);
        }
      },
    );

    test('20 bajadas seguidas sin esperar: la última emisión es el estado final', () async {
      final emisiones = <CatalogoLocal>[];
      final sub = datos.observar(_rivera).listen(emisiones.add);
      addTearDown(sub.cancel);
      await esperar(() => emisiones.isNotEmpty);
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
      });

      await Future.wait([
        for (var i = 1; i <= 20; i++)
          bajar({
            'precio_por_ciudad': [_excepcion('ppc-1', _rivera, 40000 + i, producto: 'pro-1')],
          }),
      ]);
      final esperado = await datos.leer(_rivera);
      await esperar(() => emisiones.isNotEmpty && emisiones.last == esperado);

      expect(emisiones.last, esperado);
      expect(esperado.excepciones.single.centavos, 40020);
    });

    test(
      'un cambio de parametro_global no mueve la pantalla de precios (los días se leen aparte)',
      () async {
        final emisiones = <CatalogoLocal>[];
        final sub = datos.observar(_rivera).listen(emisiones.add);
        addTearDown(sub.cancel);
        await esperar(() => emisiones.isNotEmpty);

        await bajar({
          'parametro_global': [_parametro(30)],
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(emisiones, hasLength(1));
        expect(await DiasDeAntiguedadDePreciosLocal(datos).dias(), 30);
      },
    );

    test(
      'dos filas de parametro_global con el mismo updated_at: gana siempre la misma (id mayor)',
      () async {
        await bajar({
          'parametro_global': [_parametro(10, id: 'par-a'), _parametro(20, id: 'par-b')],
        });

        final dias = DiasDeAntiguedadDePreciosLocal(datos);
        expect(await dias.dias(), 20);
        expect(await dias.dias(), 20);
      },
    );
  });

  group('ciudades y reentrada', () {
    test('dos ciudades observadas a la vez no se pisan', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
        'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        'precio_por_ciudad': [
          _excepcion('ppc-r', _rivera, 41000, producto: 'pro-1'),
          _excepcion('ppc-m', _montevideo, 48000, producto: 'pro-1'),
        ],
      });
      final r = <CatalogoLocal>[];
      final m = <CatalogoLocal>[];
      final s1 = datos.observar(_rivera).listen(r.add);
      final s2 = datos.observar(_montevideo).listen(m.add);
      addTearDown(s1.cancel);
      addTearDown(s2.cancel);
      await esperar(() => r.isNotEmpty && m.isNotEmpty);

      await bajar({
        'precio_por_ciudad': [_excepcion('ppc-m', _montevideo, 49000, producto: 'pro-1')],
      });
      await esperar(() => m.length >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(r, hasLength(1));
      expect(r.single.excepciones.single.centavos, 41000);
      expect(m.last.excepciones.single.centavos, 49000);
    });

    test(
      'cancelar y volver a escuchar (reentrada a la pantalla) entrega el catálogo de nuevo, sin errores sueltos',
      () async {
        await bajar({
          'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
          'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
        });
        final repo = ConsultaDePreciosRepositoryImpl(datos, logger: loggerMudo());

        for (var vuelta = 0; vuelta < 3; vuelta++) {
          final primero = await repo.observar(_rivera).first.timeout(const Duration(seconds: 5));
          expect(ResolvedorDePrecios.resolver(primero, dia: _hoy).map((i) => i.centavos), [45000]);
        }
      },
    );

    test('cerrar la base con la pantalla abierta no deja una excepción sin atrapar', () async {
      final eventos = <Object>[];
      final sub = datos.observar(_rivera).listen(eventos.add, onError: eventos.add);
      await esperar(() => eventos.isNotEmpty);
      await sub.cancel();
      await db.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    for (final hostil in [
      '',
      "' OR 1=1 --",
      "x'; DROP TABLE producto; --",
      '🏙️ Montevideo',
      'A' * 10000,
      'cc-RIVERA',
    ]) {
      test(
        'una ciudad que no existe (${hostil.length > 20 ? '${hostil.length} caracteres' : '«$hostil»'}) da su catálogo sin excepciones y no toca las tablas',
        () async {
          await bajar({
            'producto': [_producto('pro-1', 'Conflicto de los Siglos')],
            'precio_general': [_general('pg-1', 45000, producto: 'pro-1')],
            'precio_por_ciudad': [_excepcion('ppc-r', _rivera, 41000, producto: 'pro-1')],
          });

          final catalogo = await datos.leer(hostil);

          expect(catalogo.excepciones, isEmpty);
          expect(ResolvedorDePrecios.resolver(catalogo, dia: _hoy).map((i) => i.centavos), [45000]);
          expect((await datos.leer(_rivera)).excepciones, hasLength(1));
        },
      );
    }
  });

  group('datos límite', () {
    test(
      '2000 productos con precio se leen y se resuelven en pocos segundos',
      () async {
        await bajar({
          'producto': [
            for (var i = 0; i < 2000; i++) _producto('pro-$i', 'Libro número $i', codigo: 'COD-$i'),
          ],
          'precio_general': [
            for (var i = 0; i < 2000; i++) _general('pg-$i', 1000 + i, producto: 'pro-$i'),
          ],
          'precio_por_ciudad': [
            for (var i = 0; i < 1000; i++)
              _excepcion('ppc-$i', _rivera, 500 + i, producto: 'pro-$i'),
          ],
        });
        final reloj = Stopwatch()..start();

        final items = ResolvedorDePrecios.resolver(await datos.leer(_rivera), dia: _hoy);

        reloj.stop();
        expect(items, hasLength(2000));
        expect(
          items
              .whereType<PrecioDeProducto>()
              .firstWhere((p) => p.nombre == 'Libro número 5')
              .centavos,
          505,
        );
        expect(
          items
              .whereType<PrecioDeProducto>()
              .firstWhere((p) => p.nombre == 'Libro número 1500')
              .centavos,
          2500,
        );
        expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );

    test(
      'nombres y códigos con emoji, RTL, comillas, saltos de línea y 5000 caracteres llegan tal cual',
      () async {
        final largo = 'Ñandú ' * 900;
        final nombres = <String>[
          'El Gran Conflicto 📖',
          'كتاب عربي',
          "Dijo: \"hola\" 'x' \\ % _",
          'línea 1\nlínea 2',
          largo,
        ];
        await bajar({
          'producto': [
            for (var i = 0; i < nombres.length; i++)
              _producto('pro-$i', nombres[i], codigo: '📖-$i'),
          ],
          'precio_general': [
            for (var i = 0; i < nombres.length; i++) _general('pg-$i', 1000, producto: 'pro-$i'),
          ],
        });

        final catalogo = await datos.leer(_rivera);

        expect(catalogo.productos.map((p) => p.nombre), unorderedEquals(nombres));
        expect(catalogo.productos.map((p) => p.codigoEditor), containsAll(['📖-0', '📖-4']));
        expect(ResolvedorDePrecios.resolver(catalogo, dia: _hoy), hasLength(nombres.length));
      },
    );

    test('precio en 0 y precio muy grande llegan sin recortarse', () async {
      await bajar({
        'producto': [_producto('pro-1', 'Regalo'), _producto('pro-2', 'Caro')],
        'precio_general': [
          _general('pg-1', 0, producto: 'pro-1'),
          _general('pg-2', 9007199254740991, producto: 'pro-2'),
        ],
      });

      final catalogo = await datos.leer(_rivera);

      expect(catalogo.generales.map((g) => g.centavos), unorderedEquals([0, 9007199254740991]));
    });

    test(
      'la búsqueda del resolvedor tolera comodines, regex y emoji escritos por la usuaria',
      () async {
        await bajar({
          'producto': [_producto('pro-1', 'Conflicto (1) [a] *+?', codigo: 'A.B')],
          'precio_general': [_general('pg-1', 100, producto: 'pro-1')],
        });
        final catalogo = await datos.leer(_rivera);
        final items = ResolvedorDePrecios.resolver(catalogo, dia: _hoy);

        for (final q in ['(', '[', '*+?', '.*', r'\', '%', '🙂', '   ', 'a' * 5000]) {
          expect(() => ResolvedorDePrecios.buscar(items, q), returnsNormally, reason: 'q=$q');
        }
        expect(ResolvedorDePrecios.buscar(items, '(1)'), hasLength(1));
        expect(ResolvedorDePrecios.buscar(items, 'a.b'), hasLength(1));
        expect(ResolvedorDePrecios.buscar(items, '.*'), isEmpty);
      },
    );
  });

  group('privacidad', () {
    test('el log de una lectura fallida lleva solo el tipo del error, nunca su mensaje', () async {
      final salida = _Captura();
      final logger = AppLogger(output: salida);
      final repo = ConsultaDePreciosRepositoryImpl(_FallaUnaVez(db), logger: logger);
      final eventos = <Object>[];
      final sub = repo.observar(_rivera).listen(eventos.add, onError: eventos.add);
      addTearDown(sub.cancel);

      await esperar(() => eventos.isNotEmpty);

      final todo = salida.lineas.join('\n');
      expect(todo, contains('PRECIOS_LECTURA_FAIL'));
      expect(todo, isNot(contains('Rosa')));
      expect(todo, isNot(contains('099123456')));
      expect(eventos.single.toString(), isNot(contains('Rosa')));
    });
  });
}
