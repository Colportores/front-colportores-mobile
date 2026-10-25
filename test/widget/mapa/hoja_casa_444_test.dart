// Vista 39 (base), artboard C·01 «Tocar una casa: resumen» (HU-UBI-003, #444) y los estados del grupo
// E que la hoja engancha (#448): un test por artboard, por texto literal del canvas y por caso límite
// (doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos límite y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';

const _nbsp = ' ';

/// Lo que un test necesita después de montar la hoja.
final class _Montaje {
  final cierres = <int>[];
  var reactivaciones = 0;
  final visitas = <ContextoDeVisita>[];
  final cobros = <ContextoDeCobro>[];
  final lecturas = <ClaveDeLaCasa>[];
}

Future<_Montaje> _montar(
  WidgetTester tester, {
  ItemListaUbicacion? item,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
  FutureOr<void> Function(ContextoDeVisita, _Montaje)? registrarVisita,
  FutureOr<void> Function(ContextoDeCobro, _Montaje)? cobrar,
  bool conReactivar = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  _Montaje? montaje,
}) async {
  final m = montaje ?? _Montaje();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final casa = item ?? itemDeLaHoja();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overridesHojaCasa(
        lectura: lectura,
        lecturas: m.lecturas,
        registrarVisita: registrarVisita == null
            ? null
            : (contexto) => registrarVisita(contexto, m),
        cobrar: cobrar == null ? null : (contexto) => cobrar(contexto, m),
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: casa,
              ahora: ahoraLista,
              alCerrar: () => m.cierres.add(m.cierres.length),
              alReactivar: conReactivar
                  ? () {
                      m.reactivaciones++;
                    }
                  : null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

/// Deja correr los dos fotogramas que tarda un `Stream` en llegar a la pantalla.
Future<void> _drenar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Finder get _titulo => find.byKey(ClavesHojaCasa.titulo);
Finder get _subtitulo => find.byKey(ClavesHojaCasa.subtitulo);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _cobrar => find.byKey(ClavesHojaCasa.cobrar);
Finder get _persona => find.byKey(ClavesHojaCasa.persona);
Finder get _nota => find.byKey(ClavesHojaCasa.nota);
Finder get _cerrar => find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia);
Finder get _avisoLejos => find.byKey(ClavesEstadosHojaCasa.avisoLejos);
Finder get _avisoBaja => find.byKey(ClavesEstadosHojaCasa.avisoDadaDeBaja);
Finder get _avisoError => find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer);
Finder get _cargando => find.byKey(ClavesEstadosHojaCasa.cargando);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

String _texto(WidgetTester tester, Finder finder) => tester.widget<Text>(finder).data!;

void main() {
  group('C·01 · Tocar una casa: resumen', () {
    testWidgets('dado el canvas, muestra la dirección, el subtítulo, la persona que debe, la nota '
        'y «Registrar visita»', (tester) async {
      await _montar(tester, registrarVisita: (_, _) {}, cobrar: (_, _) {});

      expect(_texto(tester, _titulo), 'Grecia 3310');
      expect(_texto(tester, _subtitulo), 'Casa · Cobranza pendiente · a 20${_nbsp}m de vos');
      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.text('PG'), findsOneWidget);
      expect(find.text(r'Debe $ 1.200'), findsOneWidget);
      expect(find.text(r'$ Cobrar'), findsOneWidget);
      expect(find.text('NOTA DEL LUGAR'), findsOneWidget);
      expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);
      expect(find.text('✓  Registrar visita'), findsOneWidget);
      expect(find.text('✎'), findsOneWidget);
    });

    testWidgets('«Registrar visita» mide 56 dp de alto y «\$ Cobrar» y la ✕ llegan a 48 dp', (
      tester,
    ) async {
      await _montar(tester, registrarVisita: (_, _) {}, cobrar: (_, _) {});

      expect(tester.getSize(_registrar).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(_cobrar).shortestSide, greaterThanOrEqualTo(48));
      expect(tester.getSize(_cerrar).shortestSide, greaterThanOrEqualTo(48));
    });

    testWidgets('el lector de pantalla dice la persona con su deuda, la nota y los botones', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, registrarVisita: (_, _) {}, cobrar: (_, _) {});

      expect(find.bySemanticsLabel(r'Pedro Gómez. Debe $ 1.200'), findsOneWidget);
      expect(find.bySemanticsLabel(r'$ Cobrar a Pedro Gómez'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Nota del lugar. Perro suelto: tocar timbre y esperar.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Registrar visita'), findsOneWidget);
      expect(find.bySemanticsLabel('Cerrar vista previa'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el título es un encabezado para el lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      expect(
        tester.getSemantics(_titulo),
        matchesSemantics(label: 'Grecia 3310', isHeader: true, textDirection: TextDirection.ltr),
      );
      semantica.dispose();
    });

    testWidgets('«Registrar visita» abre «¿Qué pasó?» con la ubicación y el espacio de la casa', (
      tester,
    ) async {
      final m = await _montar(tester, registrarVisita: (contexto, m) => m.visitas.add(contexto));

      await tester.tap(_registrar);
      await tester.pump();

      expect(m.visitas, [(ubicacionId: 'u-1', espacioId: 'esp-1')]);
    });

    testWidgets('«\$ Cobrar» lleva la ubicación, el espacio y la persona que debe', (tester) async {
      final m = await _montar(tester, cobrar: (contexto, m) => m.cobros.add(contexto));

      await tester.tap(_cobrar);
      await tester.pump();

      expect(m.cobros, [(ubicacionId: 'u-1', espacioId: 'esp-1', personaId: 'p-pedro')]);
    });

    testWidgets('sin destino enganchado no se dibujan «Registrar visita» ni «\$ Cobrar» '
        '(no hay a dónde llevar)', (tester) async {
      await _montar(tester);

      expect(_registrar, findsNothing);
      expect(_cobrar, findsNothing);
      expect(find.text(r'Debe $ 1.200'), findsOneWidget, reason: 'la deuda se sigue diciendo');
    });

    testWidgets('«\$ Cobrar» solo va en la persona que debe: sin deuda no se dibuja', (
      tester,
    ) async {
      await _montar(
        tester,
        cobrar: (_, _) {},
        registrarVisita: (_, _) {},
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez], nota: notaDelCanvas),
        ),
      );

      expect(find.text('Pedro Gómez'), findsOneWidget);
      expect(find.textContaining('Debe'), findsNothing);
      expect(_cobrar, findsNothing);
      expect(_registrar, findsOneWidget);
    });

    testWidgets(
      'con varias personas muestra la que más debe; las demás van en la pestaña Personas',
      (tester) async {
        final ana = clienteDePersonas('p-ana', 'Ana', apellido: 'Rey', minutos: 1);
        await _montar(
          tester,
          cobrar: (_, _) {},
          lectura: (_) => Stream.value(
            ContextoDeLaCasa(
              espacioId: 'esp-1',
              personas: [pedroGomez, ana],
              saldosCentavos: const {'p-pedro': 50000, 'p-ana': 250050},
            ),
          ),
        );

        expect(_persona, findsOneWidget);
        expect(find.text('Ana Rey'), findsOneWidget);
        expect(find.text(r'Debe $ 2.500,50'), findsOneWidget);
        expect(find.text('Pedro Gómez'), findsNothing);
      },
    );

    testWidgets('sin personas ni nota muestra solo el título, el subtítulo y el botón', (
      tester,
    ) async {
      await _montar(
        tester,
        registrarVisita: (_, _) {},
        lectura: (_) => Stream.value(const ContextoDeLaCasa(espacioId: 'esp-1')),
      );

      expect(_persona, findsNothing);
      expect(_nota, findsNothing);
      expect(_registrar, findsOneWidget);
      expect(_texto(tester, _titulo), 'Grecia 3310');
    });

    testWidgets('un estado desconocido y sin GPS no se inventan: el subtítulo es solo el tipo', (
      tester,
    ) async {
      await _montar(tester, item: itemDeLaHoja(estado: null, metros: null));

      expect(_texto(tester, _subtitulo), 'Casa');
    });

    testWidgets('un negocio dice «Negocio», y un edificio no lee personas', (tester) async {
      final lecturas = <ClaveDeLaCasa>[];
      final m = _Montaje();
      await _montar(
        tester,
        montaje: m,
        item: itemDeLaHoja(tipo: TipoUbicacion.edificio, estado: EstadoCasa.sinVisita),
        lectura: (clave) {
          lecturas.add(clave);
          return Stream.value(const ContextoDeLaCasa());
        },
        registrarVisita: (contexto, m) => m.visitas.add(contexto),
      );

      expect(_texto(tester, _subtitulo), startsWith('Edificio'));
      expect(lecturas.single.tipo, TipoUbicacion.edificio);
      await tester.tap(_registrar);
      await tester.pump();
      // En un edificio el contexto es el depto: sin uno elegido, el espacio llega vacío.
      expect(m.visitas, [(ubicacionId: 'u-1', espacioId: null)]);
    });

    testWidgets(
      'si la nota o el contexto cambian mientras la hoja está abierta, la hoja los sigue',
      (tester) async {
        final emisor = StreamController<ContextoDeLaCasa>();
        addTearDown(emisor.close);
        await _montar(tester, lectura: (_) => emisor.stream);
        emisor.add(contextoDelCanvas);
        await _drenar(tester);
        expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);

        emisor.add(
          ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez], nota: notaCon('Nota nueva')),
        );
        await _drenar(tester);

        expect(find.text('Nota nueva'), findsOneWidget);
        expect(find.text('Perro suelto: tocar timbre y esperar.'), findsNothing);
        expect(find.textContaining('Debe'), findsNothing);
      },
    );

    testWidgets('la ✕ cierra la hoja', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_cerrar);
      await tester.pump();

      expect(m.cierres, hasLength(1));
    });
  });

  group('E·01 · cargando', () {
    testWidgets('mientras lee, muestra los tres esqueletos, el subtítulo vacío y nada que tocar', (
      tester,
    ) async {
      await _montar(
        tester,
        registrarVisita: (_, _) {},
        cobrar: (_, _) {},
        lectura: (_) => const Stream.empty(),
      );

      expect(_cargando, findsOneWidget);
      expect(_subtitulo, findsNothing);
      expect(_registrar, findsNothing);
      expect(_texto(tester, _titulo), 'Grecia 3310');
    });

    testWidgets('al llegar la lectura pasa al resumen', (tester) async {
      final emisor = StreamController<ContextoDeLaCasa>();
      addTearDown(emisor.close);
      await _montar(tester, lectura: (_) => emisor.stream);
      expect(_cargando, findsOneWidget);

      emisor.add(contextoDelCanvas);
      await _drenar(tester);

      expect(_cargando, findsNothing);
      expect(find.text('Pedro Gómez'), findsOneWidget);
    });
  });

  group('E·02 · error al leer', () {
    testWidgets(
      'dice «No pudimos leer esta casa en tu teléfono.» con «Reintentar» y sin subtítulo',
      (tester) async {
        await _montar(
          tester,
          registrarVisita: (_, _) {},
          lectura: (_) => Stream.error(StateError('sin base')),
        );

        expect(_avisoError, findsOneWidget);
        expect(find.text('No pudimos leer esta casa en tu teléfono.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(_subtitulo, findsNothing);
        expect(_registrar, findsNothing);
      },
    );

    testWidgets('no reintenta sola: lee una vez y espera a «Reintentar»', (tester) async {
      final m = _Montaje();
      await _montar(tester, montaje: m, lectura: (_) => Stream.error(StateError('sin base')));

      await tester.pump(const Duration(seconds: 30));

      expect(m.lecturas, hasLength(1));
    });

    testWidgets('«Reintentar» vuelve a leer y, si ahora puede, muestra el resumen', (tester) async {
      final m = _Montaje();
      var intento = 0;
      await _montar(
        tester,
        montaje: m,
        lectura: (_) => ++intento == 1
            ? Stream<ContextoDeLaCasa>.error(StateError('sin base'))
            : Stream.value(contextoDelCanvas),
      );
      expect(_avisoError, findsOneWidget);

      await tester.tap(find.byKey(ClavesEstadosHojaCasa.accionDelAviso));
      await tester.pump();
      await tester.pump();

      expect(m.lecturas, hasLength(2));
      expect(_avisoError, findsNothing);
      expect(find.text('Pedro Gómez'), findsOneWidget);
    });

    testWidgets('si «Reintentar» vuelve a fallar, el aviso sigue y se puede reintentar otra vez', (
      tester,
    ) async {
      final m = _Montaje();
      await _montar(tester, montaje: m, lectura: (_) => Stream.error(StateError('sin base')));

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(ClavesEstadosHojaCasa.accionDelAviso));
        await tester.pump();
        await tester.pump();
      }

      expect(_avisoError, findsOneWidget);
      expect(m.lecturas, hasLength(3));
    });
  });

  group('E·03 · sin conexión', () {
    testWidgets('la hoja se lee del teléfono: se ve igual que el resumen, sin ningún aviso', (
      tester,
    ) async {
      await _montar(tester, registrarVisita: (_, _) {});

      expect(_avisoError, findsNothing);
      expect(_avisoBaja, findsNothing);
      expect(_avisoLejos, findsNothing);
      expect(_registrar, findsOneWidget);
    });
  });

  group('E·04 · casa dada de baja', () {
    final baja = DateTime.utc(2026, 10, 18, 15);

    testWidgets(
      'muestra el aviso con «Reactivar», el subtítulo «dada de baja el 18/10» y lo que había '
      'solo para ver',
      (tester) async {
        await _montar(
          tester,
          item: itemDeLaHoja(baja: baja, estado: null, metros: 650),
          registrarVisita: (_, _) {},
          cobrar: (_, _) {},
        );

        expect(
          find.text('Esta casa está dada de baja: podés ver lo que pasó, pero no registrar nada.'),
          findsOneWidget,
        );
        expect(find.text('Reactivar'), findsOneWidget);
        expect(_texto(tester, _subtitulo), 'Casa · dada de baja el 18/10');
        expect(find.text('Pedro Gómez'), findsOneWidget);
        expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);
      },
    );

    testWidgets('no se registra nada: ni «Registrar visita» ni «\$ Cobrar» (aunque haya destino)', (
      tester,
    ) async {
      await _montar(
        tester,
        item: itemDeLaHoja(baja: baja),
        registrarVisita: (_, _) {},
        cobrar: (_, _) {},
      );

      expect(_registrar, findsNothing);
      expect(_cobrar, findsNothing);
    });

    testWidgets('con la baja va solo el aviso de baja: no el de «Estás a 650 m»', (tester) async {
      await _montar(tester, item: itemDeLaHoja(baja: baja, metros: 650));

      expect(_avisoBaja, findsOneWidget);
      expect(_avisoLejos, findsNothing);
    });

    testWidgets('«Reactivar» llama a quien reactiva', (tester) async {
      final m = await _montar(tester, item: itemDeLaHoja(baja: baja));

      await tester.tap(find.byKey(ClavesEstadosHojaCasa.accionDelAviso));
      await tester.pump();

      expect(m.reactivaciones, 1);
    });

    testWidgets('si la baja no se reactiva (unión de duplicados) el aviso va sin acción', (
      tester,
    ) async {
      await _montar(tester, item: itemDeLaHoja(baja: baja), conReactivar: false);

      expect(_avisoBaja, findsOneWidget);
      expect(find.byKey(ClavesEstadosHojaCasa.accionDelAviso), findsNothing);
    });
  });

  group('E·05 · lejos de la casa', () {
    testWidgets('a 650 m avisa «Estás a 650 m de esta casa.» y deja registrar la visita', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        item: itemDeLaHoja(metros: 650),
        registrarVisita: (contexto, m) => m.visitas.add(contexto),
      );

      expect(find.text('Estás a 650${_nbsp}m de esta casa.'), findsOneWidget);
      await tester.tap(_registrar);
      await tester.pump();
      expect(m.visitas, hasLength(1), reason: 'el aviso no frena ni pide confirmar');
    });

    testWidgets(
      'el umbral es 100 m: a 99 m no avisa y a 100 m sí (decisión de Cristian del 23/10)',
      (tester) async {
        await _montar(tester, item: itemDeLaHoja(metros: 99));
        expect(_avisoLejos, findsNothing);

        await _montar(tester, item: itemDeLaHoja(metros: 100));
        expect(_avisoLejos, findsOneWidget);
        expect(find.text('Estás a 100${_nbsp}m de esta casa.'), findsOneWidget);
      },
    );

    testWidgets('sin posición del colportor no avisa nada', (tester) async {
      await _montar(tester, item: itemDeLaHoja(metros: null));

      expect(_avisoLejos, findsNothing);
    });

    testWidgets('en kilómetros dice «Estás a 1,5 km de esta casa.»', (tester) async {
      await _montar(tester, item: itemDeLaHoja(metros: 1500));

      expect(find.text('Estás a 1,5${_nbsp}km de esta casa.'), findsOneWidget);
    });
  });

  group('Casos límite de «Registrar visita» y «\$ Cobrar»', () {
    testWidgets('doble toque rápido: abre una sola vez', (tester) async {
      final m = await _montar(
        tester,
        registrarVisita: (contexto, m) async {
          m.visitas.add(contexto);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        },
      );

      await tester.tap(_registrar);
      await tester.tap(_registrar);
      await tester.pump(const Duration(milliseconds: 300));

      expect(m.visitas, hasLength(1));
    });

    testWidgets('mientras abre queda apagado y, al terminar, vuelve a poder tocarse', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final m = await _montar(
        tester,
        registrarVisita: (contexto, m) {
          m.visitas.add(contexto);
          return compuerta.future;
        },
      );

      await tester.tap(_registrar);
      await tester.pump();
      expect(_habilitado(tester, _registrar), isFalse);

      compuerta.complete();
      await tester.pump();
      await tester.pump();

      expect(_habilitado(tester, _registrar), isTrue);
      expect(m.visitas, hasLength(1));
    });

    testWidgets(
      'si abrir falla a mitad: la hoja lo dice, el botón vuelve a habilitarse y reintenta',
      (tester) async {
        var intento = 0;
        final m = await _montar(
          tester,
          registrarVisita: (contexto, m) {
            m.visitas.add(contexto);
            if (++intento == 1) throw StateError('no abrió');
          },
        );

        await tester.tap(_registrar);
        await tester.pump();
        await tester.pump();

        expect(find.text('No pudimos abrir «Registrar visita». Probá de nuevo.'), findsOneWidget);
        expect(_habilitado(tester, _registrar), isTrue);

        await tester.tap(_registrar);
        await tester.pump();
        await tester.pump();

        expect(m.visitas, hasLength(2));
        expect(find.textContaining('No pudimos abrir'), findsNothing);
      },
    );

    testWidgets('si falla de forma asíncrona (Future con error) pasa lo mismo', (tester) async {
      final m = await _montar(
        tester,
        registrarVisita: (contexto, m) async {
          m.visitas.add(contexto);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          throw StateError('tarde');
        },
      );

      await tester.tap(_registrar);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.textContaining('No pudimos abrir'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
      expect(m.visitas, hasLength(1));
    });

    testWidgets('«\$ Cobrar» que falla dice su propio aviso y vuelve a poder tocarse', (
      tester,
    ) async {
      var intento = 0;
      final m = await _montar(
        tester,
        registrarVisita: (_, _) {},
        cobrar: (contexto, m) {
          m.cobros.add(contexto);
          if (++intento == 1) throw StateError('no abrió');
        },
      );

      await tester.tap(_cobrar);
      await tester.pump();
      await tester.pump();
      expect(find.text(r'No pudimos abrir «$ Cobrar». Probá de nuevo.'), findsOneWidget);

      await tester.tap(_cobrar);
      await tester.pump();

      expect(m.cobros, hasLength(2));
    });

    testWidgets('dos acciones seguidas antes de que termine la primera: la segunda se ignora', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      final m = await _montar(
        tester,
        registrarVisita: (contexto, m) {
          m.visitas.add(contexto);
          return compuerta.future;
        },
        cobrar: (contexto, m) => m.cobros.add(contexto),
      );

      await tester.tap(_registrar);
      await tester.tap(_cobrar);
      await tester.pump();

      expect(m.visitas, hasLength(1));
      expect(m.cobros, isEmpty, reason: '«\$ Cobrar» quedó apagado mientras abre la visita');

      compuerta.complete();
      await tester.pump();
      await tester.pump();
      await tester.tap(_cobrar);
      await tester.pump();

      expect(m.cobros, hasLength(1), reason: 'al terminar la primera, la otra vuelve a andar');
    });

    testWidgets('si la hoja se cierra mientras la acción corre, no revienta al terminar', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      await _montar(tester, registrarVisita: (_, _) => compuerta.future);
      await tester.tap(_registrar);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      compuerta.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('si la acción falla con la hoja ya cerrada, tampoco', (tester) async {
      final compuerta = Completer<void>();
      await _montar(tester, registrarVisita: (_, _) => compuerta.future);
      await tester.tap(_registrar);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      compuerta.completeError(StateError('tarde'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets(
      'una hoja nueva de la misma casa arranca sin lo ocupado ni el aviso de la anterior',
      (tester) async {
        final compuerta = Completer<void>();
        await _montar(tester, registrarVisita: (_, _) => compuerta.future);
        await tester.tap(_registrar);
        await tester.pump();
        expect(_habilitado(tester, _registrar), isFalse);

        // Se cierra y se vuelve a abrir la misma casa: otra hoja, otro estado.
        await _montar(tester, registrarVisita: (_, _) {});

        expect(_habilitado(tester, _registrar), isTrue);
        expect(find.textContaining('No pudimos'), findsNothing);
        compuerta.complete();
      },
    );

    testWidgets('al reentrar vuelve a leer la casa: un cambio hecho mientras tanto se ve', (
      tester,
    ) async {
      var nota = notaDelCanvas;
      Stream<ContextoDeLaCasa> lectura(ClaveDeLaCasa _) =>
          Stream.value(ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez], nota: nota));
      await _montar(tester, lectura: lectura);
      expect(find.text('Perro suelto: tocar timbre y esperar.'), findsOneWidget);

      nota = notaCon('Cambió mientras estaba cerrada');
      await _montar(tester, lectura: lectura);

      expect(find.text('Cambió mientras estaba cerrada'), findsOneWidget);
    });
  });

  group('Datos límite', () {
    final largo = 'Muy ' * 60;

    testWidgets('textos larguísimos a 200 % en 320 × 568: nada se desborda y el botón se alcanza', (
      tester,
    ) async {
      await _montar(
        tester,
        escala: 2,
        tamano: const Size(320, 568),
        item: itemDeLaHoja(calle: 'Avenida ${largo}Larga', numero: '1234 bis', metros: 650),
        registrarVisita: (_, _) {},
        cobrar: (_, _) {},
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [clienteDePersonas('p-largo', 'Nombre$largo', apellido: 'Apellido$largo')],
            saldosCentavos: const {'p-largo': 99999999},
            nota: notaCon(largo * 5),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(_registrar, 200, scrollable: find.byType(Scrollable).first);
      expect(_registrar, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 200 % «\$ Cobrar» baja debajo de la persona y se sigue pudiendo tocar', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        escala: 2,
        tamano: const Size(320, 568),
        cobrar: (contexto, m) => m.cobros.add(contexto),
      );

      await tester.scrollUntilVisible(_cobrar, 100, scrollable: find.byType(Scrollable).first);
      await tester.tap(_cobrar);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(m.cobros, hasLength(1));
      expect(
        tester.getTopLeft(_cobrar).dy,
        greaterThan(tester.getBottomLeft(find.text('Pedro Gómez')).dy),
      );
    });

    testWidgets('una nota larga se corta a tres renglones y el lector la dice entera', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final texto = 'Perro suelto, tocar timbre y esperar. ' * 20;
      await _montar(
        tester,
        lectura: (_) => Stream.value(ContextoDeLaCasa(espacioId: 'esp-1', nota: notaCon(texto))),
      );

      final nota = tester.widget<Text>(find.text(texto));
      expect(nota.maxLines, 3);
      expect(nota.overflow, TextOverflow.ellipsis);
      expect(find.bySemanticsLabel(RegExp('^Nota del lugar. Perro suelto')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('una persona sin apellido muestra una sola inicial', (tester) async {
      await _montar(
        tester,
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(espacioId: 'esp-1', personas: [clienteDePersonas('p-1', 'Madonna')]),
        ),
      );

      expect(find.text('M'), findsOneWidget);
      expect(find.text('Madonna'), findsOneWidget);
    });

    testWidgets('los nombres y la nota no salen en el toString del contexto (PII)', (tester) async {
      expect(contextoDelCanvas.toString(), isNot(contains('Pedro')));
      expect(contextoDelCanvas.toString(), isNot(contains('Perro suelto')));
      expect(notaDelCanvas.toString(), isNot(contains('Perro suelto')));
    });
  });
}
