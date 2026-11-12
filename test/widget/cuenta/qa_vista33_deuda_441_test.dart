// QA de la deuda con la casa editora (vista 33A·01 y 33B, HU-CTA-002, #441).
//
// Qué cubre (sin fuentes reales: los contrastes dan falsos negativos con ellas, ver el archivo
// `_fuentes_`):
// - los 10 estados de 33B y los 5 de la tarjeta de Mi Cuenta en 360x640 y 412x915, con el texto a
//   1,0 y 2,0: sin overflow, tamaño de toque (Android e iOS), nombre en lo tocable y contraste;
// - la lectura real (repositorio + caché en memoria) de punta a punta: guardar, cortar la red, volver;
// - los hallazgos de QA: los ya arreglados corren; los que siguen abiertos van con `skip: true` y el comentario `QA #441: …`.
import 'dart:convert';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/deuda_con_la_casa_cache_data_source.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/deuda_con_la_casa_remote_data_source.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/deuda_con_la_casa_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/deuda_casa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';
import '../../helpers/qa_vista33_deuda_441_arnes.dart';

const _tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
const _escalas = [1.0, 2.0];

/// Una caché en memoria para el repositorio real.
final class _CacheEnMemoria implements DeudaConLaCasaCacheDataSource {
  DeudaGuardada? guardada;
  @override
  Future<DeudaGuardada?> leer(String colportorId) async => guardada;
  @override
  Future<void> guardar(String colportorId, String respuesta, DateTime leidaEn) async =>
      guardada = (respuesta: respuesta, leidaEn: leidaEn);
}

/// Un servidor que contesta lo que el test le dé.
final class _Servidor implements DeudaConLaCasaRemoteDataSource {
  Object? respuesta;
  Object? falla;
  var llamadas = 0;
  @override
  Future<Object?> leer() async {
    llamadas++;
    if (falla != null) throw falla!;
    return respuesta;
  }
}

Map<String, Object?> _json({int total = 1840000, int suma = 1840000}) => {
  'deuda_total': total,
  'suma_de_saldos': suma,
  'depositos_validados': 0,
  'pedidos': [
    {
      'pedido_id': 'p-1',
      'fecha_pedido': '2026-10-02T15:00:00Z',
      'monto': 1840000,
      'pagado': 0,
      'saldo': 1840000,
      'lineas': [
        {'nombre': 'Salud y Hogar', 'cantidad': 10},
      ],
    },
  ],
};

void main() {
  for (final estado in EstadoQa33B.values) {
    group('33B · ${estado.name}', () {
      for (final t in _tamanos.entries) {
        for (final esc in _escalas) {
          testWidgets('${t.key} · texto ${esc}x: sin overflow y con las guías de accesibilidad', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await repoEnEstado(
              tester,
              estado,
              (repo) => montarDeuda(tester, repo, tamano: t.value, escala: esc),
            );
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            if (esc == 1.0) {
              await expectLater(tester, meetsGuideline(textContrastGuideline));
            }
            handle.dispose();
          });
        }
      }
    });
  }

  for (final estado in EstadoQa33A.values) {
    group('33A · tarjeta de la deuda · ${estado.name}', () {
      for (final t in _tamanos.entries) {
        for (final esc in _escalas) {
          testWidgets('${t.key} · texto ${esc}x: sin overflow y con las guías de accesibilidad', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await montarCuentaEnEstado(tester, estado, tamano: t.value, escala: esc);
            expect(tester.takeException(), isNull);
            expect(find.byKey(const Key('cuenta_deuda')), findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            if (esc == 1.0) {
              await expectLater(tester, meetsGuideline(textContrastGuideline));
            }
            handle.dispose();
          });
        }
      }
    });
  }

  group('Literales del canvas y de la HU', () {
    testWidgets('33B·01: «Dado que tengo 3 pedidos con deuda, cuando abro «Deuda con casa '
        'editora», entonces se listan los 3 con saldos y el total al header»', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(
        lectura(
          deuda(
            total: 30000,
            pedidos: [
              for (var i = 1; i <= 3; i++)
                pedido('p-$i', DateTime.utc(2026, 10, i * 5, 15), monto: 10000, pagado: 0),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Deuda con la casa editora'), findsOneWidget);
      expect(find.text(r'$ 30.000'), findsOneWidget);
      expect(find.text('PEDIDOS CON SALDO'), findsOneWidget);
      expect(find.text('PEDIDO DEL 05/10'), findsOneWidget);
      expect(find.text('PEDIDO DEL 10/10'), findsOneWidget);
      expect(find.text('PEDIDO DEL 15/10'), findsOneWidget);
      expect(find.text(r'Saldo $ 10.000'), findsNWidgets(3));
      expect(find.text(r'Pedido $ 10.000 · pagado $ 0'), findsNWidgets(3));
    });

    testWidgets('33B·02: sin deuda, total «\$ 0» y «No le debés nada a la casa editora»', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(lectura(deuda(total: 0)));
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 0'), findsOneWidget);
      expect(find.text('No le debés nada a la casa editora'), findsOneWidget);
      expect(find.text('PEDIDOS CON SALDO'), findsNothing);
    });
  });

  group('Casos límite que no estaban', () {
    testWidgets('lo guardado cambia a «sin deuda» mientras se mira: no queda el pedido viejo ni '
        'el aviso', (tester) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await montarDeuda(tester, repo);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      repo.responder(lectura(deuda(total: 0)));
      await tester.pump();
      await tester.pump();
      expect(find.text('PEDIDO DEL 02/10'), findsNothing);
      expect(find.text('No le debés nada a la casa editora'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
    });

    testWidgets('a favor y con pedidos con saldo: dice «A favor», la lista y la aclaración, sin '
        'romperse', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo, tamano: const Size(360, 640), escala: 2);
      repo.responder(
        lectura(
          deuda(
            total: -1200,
            suma: 5000,
            pedidos: [pedido('p-1', DateTime.utc(2026, 10, 2, 15), monto: 5000, pagado: 0)],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('A favor'), findsOneWidget);
      expect(find.byKey(const Key('deuda_a_favor_explica')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('deuda_pedido_0')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('deuda_pedido_0')), findsOneWidget);
    });

    testWidgets('el volver mientras carga y reentrar no deja nada trabado', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      // Lo que llega con la pantalla ya cerrada se descarta sin excepción.
      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Lectura real de punta a punta (repositorio + caché + pantalla)', () {
    testWidgets('con red se ve y se guarda; sin red, la 2ª vez se ve lo guardado con su hora y '
        '«Reintentar» no hace falta', (tester) async {
      final servidor = _Servidor()..respuesta = _json();
      final cache = _CacheEnMemoria();
      final repo = DeudaConLaCasaRepositoryImpl(
        servidor,
        cache,
        ahora: () => DateTime.utc(2026, 11, 3, 21),
      );
      // Primera apertura, con red.
      await _montarConRepo(tester, repo);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(cache.guardada, isNotNull);
      expect(jsonDecode(cache.guardada!.respuesta), isA<Map<String, Object?>>());

      // Segunda apertura, sin red: el servidor cortó.
      await tester.pumpWidget(const SizedBox());
      servidor.falla = const DeudaSinConexionException();
      await _montarConRepo(tester, repo);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('cuenta_aviso_sin_conexion'))).data,
        contains('Sin conexión'),
      );
      expect(find.text('No pudimos traer tus pedidos.'), findsNothing);
    });

    testWidgets('una respuesta rara del servidor no pisa lo guardado ni se muestra', (
      tester,
    ) async {
      final servidor = _Servidor()..respuesta = _json();
      final cache = _CacheEnMemoria();
      final repo = DeudaConLaCasaRepositoryImpl(
        servidor,
        cache,
        ahora: () => DateTime.utc(2026, 11, 3, 21),
      );
      await _montarConRepo(tester, repo);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final guardadaAntes = cache.guardada!.respuesta;

      await tester.pumpWidget(const SizedBox());
      servidor.respuesta = {'deuda_total': 'mucho'};
      await _montarConRepo(tester, repo);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(cache.guardada!.respuesta, guardadaAntes);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('cuenta_error_texto'))).data,
        startsWith('No pudimos actualizarla'),
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('HALLAZGOS', () {
    // Decisión P3 del 04/11 (aplicada en 541afb76): con horas distintas el aviso nombra la de la deuda.
    testWidgets(
      'Mi Cuenta sin conexión: si la deuda guardada es de otra hora que «Depositado», el aviso '
      'suma «La deuda con la casa editora es de <hora>.»',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(
          guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 18)),
        );
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenConDepositado441()),
          overrides: [
            ...overridesDeDeuda(repo),
            monitorConectividadProvider.overrideWithValue(QaConexion(TipoConexion.sinConexion)),
          ],
        );
        await tester.pump();
        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();
        final aviso = tester.widget<Text>(find.byKey(const Key('cuenta_aviso_sin_conexion')));
        expect(aviso.data, contains('La deuda con la casa editora es de'));
        expect(aviso.data, contains('18:00'));
      },
    );

    // Decisión §2 (QA P3, 04/11): con las horas iguales va el literal del canvas 33A·02.
    testWidgets(
      'Mi Cuenta sin conexión: con la misma hora, el aviso es el del canvas 33A·02 («La deuda y lo '
      'depositado son de …; en mano y por cobrar están al día.»)',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(
          guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 10, 29, 21)),
        );
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenConDepositado441()),
          overrides: [
            ...overridesDeDeuda(repo),
            monitorConectividadProvider.overrideWithValue(QaConexion(TipoConexion.sinConexion)),
          ],
        );
        await tester.pump();
        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();
        final aviso = tester.widget<Text>(find.byKey(const Key('cuenta_aviso_sin_conexion')));
        expect(aviso.data, contains('La deuda y lo depositado son del 29/10 a las 21:00'));
        expect(aviso.data, isNot(contains('La deuda con la casa editora es de')));
      },
    );

    // Decisión §2 (QA P4, 04/11): sin «Depositado» bajado el aviso sale igual, con la hora de la deuda.
    testWidgets(
      'Mi Cuenta sin conexión y sin «Depositado» bajado: la deuda guardada de ayer no se ve '
      'como actual (el aviso nombra su hora)',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(
          guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 18)),
        );
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
          overrides: [
            ...overridesDeDeuda(repo),
            monitorConectividadProvider.overrideWithValue(QaConexion(TipoConexion.sinConexion)),
          ],
        );
        await tester.pump();
        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();
        expect(find.text(r'$ 18.400'), findsOneWidget);
        expect(find.textContaining('La deuda con la casa editora es de'), findsOneWidget);
      },
    );

    // skip: issue #441 — el esqueleto de Mi Cuenta tiene 3 bloques y el canvas 33A·03 dibuja 4.
    testWidgets(
      '33A·03: el esqueleto de Mi Cuenta tiene un bloque por cada una de las 4 tarjetas',
      (tester) async {
        await montarCuenta(tester, RepositorioDeCuentaControlable());
        final bloques = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('cuenta_esqueleto_'),
        );
        expect(bloques, findsNWidgets(4));
      },
      // QA #441: el esqueleto de Mi Cuenta (33A·03) tiene 3 bloques y el canvas dibuja 4 (falta el
      // de la deuda).
      skip: true,
    );

    // Decisión §2 (QA P1, 04/11): sin conexión y sin nada guardado, 33B dice que hace falta conexión.
    testWidgets('33B sin conexión y sin nada guardado: el aviso dice que hace falta conexión '
        '(«Necesitás conexión para ver tu deuda…», convenciones §sin conexión)', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Necesitás conexión'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    // skip: issue #441 — el aviso de lo guardado de 33B no es región viva (heredado de #611).
    testWidgets(
      '33B: el aviso de sin conexión con lo guardado se anuncia al lector (región viva)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepositorioDeDeudaControlable(
          guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 21)),
        );
        await montarDeuda(tester, repo);
        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();
        final nodo = tester.getSemantics(find.byKey(const Key('cuenta_aviso_sin_conexion')));
        var viva = false;
        void mirar(SemanticsNode n) {
          if (n.getSemanticsData().flagsCollection.isLiveRegion) viva = true;
          n.visitChildren((h) {
            mirar(h);
            return true;
          });
        }

        SemanticsNode raiz = nodo;
        while (raiz.parent != null) {
          if (raiz.getSemanticsData().flagsCollection.isLiveRegion) viva = true;
          raiz = raiz.parent!;
        }
        mirar(nodo);
        expect(viva, isTrue);
        handle.dispose();
      },
      // QA #441: el aviso «Sin conexión. Esta deuda es de …» de 33B no es región viva: el lector no
      // lo anuncia al aparecer (heredado de #611).
      skip: true,
    );
  });
}

Future<void> _montarConRepo(WidgetTester tester, DeudaConLaCasaRepositoryImpl repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deudaConLaCasaRepositoryProvider.overrideWithValue(repo),
        relojCuentaProvider.overrideWithValue(() => DateTime(2026, 11, 4, 10)),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: const DeudaCasaPage(colportorId: 'col-1'),
      ),
    ),
  );
}
