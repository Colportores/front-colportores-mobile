// Vista 39 (base), grupo E «Estados y casos límite» (HU-UBI-003 y HU-UBI-005, #448): un test por
// artboard (E·01 a E·06), por aviso literal del canvas y por caso límite (doble toque, falla a mitad,
// dos acciones seguidas, volver y reentrar, datos límite y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/modificar_ubicacion_falsos.dart';

const _nbsp = ' ';

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool conScroll = false,
  double? alto,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget cuerpo = Padding(padding: const EdgeInsets.all(16), child: hijo);
  if (alto != null) cuerpo = SizedBox(height: alto, child: cuerpo);
  if (conScroll) cuerpo = SingleChildScrollView(child: cuerpo);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(alignment: Alignment.topCenter, child: cuerpo),
      ),
    ),
  );
}

Finder get _accion => find.byKey(ClavesEstadosHojaCasa.accionDelAviso);

bool _habilitada(WidgetTester tester) => tester.widget<TextButton>(_accion).onPressed != null;

ItemListaUbicacion _item(
  String id, {
  String? calle = 'Grecia',
  String? numero = '3310',
  TipoUbicacion tipo = TipoUbicacion.casa,
  EstadoCasa? estado,
  DateTime? baja,
}) => ItemListaUbicacion(
  ubicacion: ubicacionGuardada(id: id, calle: calle, numero: numero, tipo: tipo, deBajaDesde: baja),
  estado: estado,
);

List<ItemListaUbicacion> get _tres => [
  _item('u-1', estado: EstadoCasa.cobranzaPendiente),
  _item('u-2', numero: '3310 bis', estado: EstadoCasa.noContesto),
  _item('u-3', tipo: TipoUbicacion.negocio, estado: EstadoCasa.sinVisita),
];

void main() {
  group('E·01 · Cargando la casa', () {
    testWidgets('dado que la casa se está leyendo, entonces muestra tres barras quietas y se '
        'anuncia «Cargando la casa»', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, const CargandoHojaCasa());

      expect(find.byKey(ClavesEstadosHojaCasa.cargando), findsOneWidget);
      final barras = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(ClavesEstadosHojaCasa.cargando),
              matching: find.byType(Container),
            ),
          )
          .toList();
      expect(barras, hasLength(3));
      expect(barras.map((c) => tester.getSize(find.byWidget(c)).height), [52, 52, 20]);
      final nodo = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.cargando));
      expect(nodo.label, 'Cargando la casa');
      // Sin animación: pasa el tiempo y no queda nada agendado.
      await tester.pump(const Duration(seconds: 5));
      expect(tester.binding.hasScheduledFrame, isFalse);
      semantica.dispose();
    });

    testWidgets('no ofrece nada para tocar mientras carga', (tester) async {
      await _montar(tester, const CargandoHojaCasa());

      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a 320×568 con el texto al 200 % no desborda', (tester) async {
      await _montar(tester, const CargandoHojaCasa(), escala: 2, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
    });

    testWidgets('volver atrás y reentrar vuelve a mostrarlo igual', (tester) async {
      await _montar(tester, const CargandoHojaCasa());
      await tester.pumpWidget(const SizedBox.shrink());
      await _montar(tester, const CargandoHojaCasa());

      expect(find.byKey(ClavesEstadosHojaCasa.cargando), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('E·02 · Error al leer la casa', () {
    testWidgets('muestra el aviso literal con «Reintentar» y se anuncia como región viva', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () {}));

      expect(find.text('No pudimos leer esta casa en tu teléfono.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
      final nodo = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('«Reintentar» llama a la lectura una vez', (tester) async {
      var llamadas = 0;
      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () => llamadas++));

      await tester.tap(_accion);
      await tester.pump();

      expect(llamadas, 1);
      expect(_habilitada(tester), isTrue);
    });

    testWidgets('doble toque: la lectura arranca una sola vez mientras la primera sigue', (
      tester,
    ) async {
      final lectura = Completer<void>();
      var llamadas = 0;
      await _montar(
        tester,
        AvisoHojaCasa.errorAlLeer(
          alReintentar: () {
            llamadas++;
            return lectura.future;
          },
        ),
      );

      await tester.tap(_accion);
      await tester.tap(_accion);
      await tester.pump();

      expect(llamadas, 1);
      expect(_habilitada(tester), isFalse);
      lectura.complete();
      await tester.pump();
      expect(_habilitada(tester), isTrue);
    });

    testWidgets('si la lectura falla a mitad, «Reintentar» vuelve a habilitarse y se puede '
        'tocar de nuevo', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        AvisoHojaCasa.errorAlLeer(
          alReintentar: () async {
            llamadas++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            throw StateError('falló');
          },
        ),
      );

      await tester.tap(_accion);
      await tester.pump();
      expect(_habilitada(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(_habilitada(tester), isTrue);
      await tester.tap(_accion);
      await tester.pump();
      expect(llamadas, 2);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('dos reintentos seguidos, cada uno cuando terminó el anterior, se hacen los dos', (
      tester,
    ) async {
      final lecturas = <Completer<void>>[];
      await _montar(
        tester,
        AvisoHojaCasa.errorAlLeer(
          alReintentar: () {
            final c = Completer<void>();
            lecturas.add(c);
            return c.future;
          },
        ),
      );

      await tester.tap(_accion);
      await tester.pump();
      lecturas.first.complete();
      await tester.pump();
      await tester.tap(_accion);
      await tester.pump();

      expect(lecturas, hasLength(2));
    });

    testWidgets('volver atrás mientras lee: al terminar no pasa nada, y al reentrar el botón está '
        'habilitado', (tester) async {
      final lectura = Completer<void>();
      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () => lectura.future));
      await tester.tap(_accion);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      lectura.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () {}));
      expect(_habilitada(tester), isTrue);
    });

    testWidgets('el botón mide al menos 48×48 y tiene nombre para el lector', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () {}));

      final tamano = tester.getSize(_accion);
      expect(tamano.height, greaterThanOrEqualTo(48));
      expect(tamano.width, greaterThanOrEqualTo(48));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('a 320×568 al 200 % y 300 % el aviso y «Reintentar» se leen enteros', (
      tester,
    ) async {
      for (final escala in [2.0, 3.0]) {
        await _montar(
          tester,
          AvisoHojaCasa.errorAlLeer(alReintentar: () {}),
          escala: escala,
          tamano: const Size(320, 568),
          conScroll: true,
        );
        expect(tester.takeException(), isNull, reason: 'escala $escala');
        expect(find.text('No pudimos leer esta casa en tu teléfono.'), findsOneWidget);
        expect(_accion, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('E·03 · Sin conexión', () {
    testWidgets('no tiene aviso: ningún texto de los estados de la hoja habla de la conexión', (
      tester,
    ) async {
      await _montar(
        tester,
        Column(
          children: [
            AvisoHojaCasa.errorAlLeer(alReintentar: () {}),
            AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
            AvisoHojaCasa.lejos(metros: 650),
            ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {}),
          ],
        ),
        conScroll: true,
      );

      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => (t.data ?? '').toLowerCase());
      expect(textos.where((t) => t.contains('conexión') || t.contains('internet')), isEmpty);
    });
  });

  group('E·04 · Casa dada de baja', () {
    testWidgets('muestra el aviso literal ámbar con «Reactivar»', (tester) async {
      await _montar(tester, AvisoHojaCasa.dadaDeBaja(alReactivar: () {}));

      expect(
        find.text('Esta casa está dada de baja: podés ver lo que pasó, pero no registrar nada.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Reactivar'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });

    testWidgets('«Reactivar» abre la reactivación una sola vez aunque se toque dos veces', (
      tester,
    ) async {
      final hoja = Completer<void>();
      var aperturas = 0;
      await _montar(
        tester,
        AvisoHojaCasa.dadaDeBaja(
          alReactivar: () {
            aperturas++;
            return hoja.future;
          },
        ),
      );

      await tester.tap(_accion);
      await tester.tap(_accion);
      await tester.pump();

      expect(aperturas, 1);
      hoja.complete();
      await tester.pump();
      expect(_habilitada(tester), isTrue);
    });

    testWidgets('si la reactivación falla, «Reactivar» vuelve a estar habilitado', (tester) async {
      await _montar(
        tester,
        AvisoHojaCasa.dadaDeBaja(alReactivar: () async => throw StateError('falló')),
      );

      await tester.tap(_accion);
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_habilitada(tester), isTrue);
    });

    testWidgets('sin acción para reactivar (baja por unión) el aviso va solo, sin botón', (
      tester,
    ) async {
      await _montar(tester, AvisoHojaCasa.dadaDeBaja());

      expect(find.textContaining('dada de baja'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('el subtítulo de la hoja dice «Casa · dada de baja el 18/10»', (tester) async {
      expect(
        TextosEstadosHojaCasa.subtituloDeBaja(TipoUbicacion.casa, DateTime(2026, 10, 18, 9)),
        'Casa · dada de baja el 18/10',
      );
      expect(
        TextosEstadosHojaCasa.subtituloDeBaja(TipoUbicacion.edificio, DateTime(2026, 1, 3)),
        'Edificio · dada de baja el 03/01',
      );
    });

    testWidgets('a 320×568 al 300 % el aviso entero se lee y no desborda', (tester) async {
      await _montar(
        tester,
        AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
        escala: 3,
        tamano: const Size(320, 568),
        conScroll: true,
      );

      expect(tester.takeException(), isNull);
      expect(_accion, findsOneWidget);
    });
  });

  group('E·05 · Lejos de la casa', () {
    testWidgets('«Estás a 650 m de esta casa.» solo informa: sin botón que bloquee o confirme', (
      tester,
    ) async {
      await _montar(tester, AvisoHojaCasa.lejos(metros: 650));

      expect(find.text('Estás a 650${_nbsp}m de esta casa.'), findsOneWidget);
      expect(find.text('i'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('las distancias límite: cerca de 0 es «1 m», desde 1000 va en km', (tester) async {
      expect(TextosEstadosHojaCasa.lejos(0), 'Estás a 1${_nbsp}m de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(999.4), 'Estás a 999${_nbsp}m de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(1000), 'Estás a 1,0${_nbsp}km de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(3200), 'Estás a 3,2${_nbsp}km de esta casa.');
    });

    testWidgets('una distancia que no existe no dibuja el aviso (nunca «Estás a  de esta casa»)', (
      tester,
    ) async {
      for (final metros in [double.nan, double.infinity, -5.0]) {
        expect(TextosEstadosHojaCasa.lejos(metros), isEmpty);
        await _montar(tester, AvisoHojaCasa.lejos(metros: metros));
        expect(find.textContaining('Estás a'), findsNothing, reason: '$metros');
        expect(find.byType(InsigniaCirculo), findsNothing, reason: '$metros');
      }
    });

    testWidgets('se anuncia como región viva y cumple contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, AvisoHojaCasa.lejos(metros: 650));

      final nodo = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.avisoLejos));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      expect(nodo.label, contains('Estás a 650'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('a 320×568 al 300 % no desborda', (tester) async {
      await _montar(
        tester,
        AvisoHojaCasa.lejos(metros: 123456),
        escala: 3,
        tamano: const Size(320, 568),
        conScroll: true,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('E·06 · Varias ubicaciones en el mismo punto', () {
    testWidgets('muestra «3 ubicaciones acá», «Elegí cuál» y una fila por ubicación con su '
        'estado', (tester) async {
      await _montar(tester, ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {}));

      expect(find.text('3 ubicaciones acá'), findsOneWidget);
      expect(find.text('Elegí cuál'), findsOneWidget);
      // La casa y el negocio comparten la dirección: se distinguen por el tipo y el estado.
      expect(find.text('Grecia 3310'), findsNWidgets(2));
      expect(find.text('Casa · Cobranza pendiente'), findsOneWidget);
      expect(find.text('Grecia 3310 bis'), findsOneWidget);
      expect(find.text('Casa · No contestó'), findsOneWidget);
      // Sin visita no tiene glifo propio: la fila lleva el ícono del tipo.
      expect(find.text('Negocio · Sin visita'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
      expect(find.text('›'), findsNWidgets(3));
    });

    testWidgets('tocar una fila elige esa ubicación', (tester) async {
      final elegidas = <String>[];
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (i) => elegidas.add(i.ubicacion.id)),
      );

      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-2')));
      await tester.pump();

      expect(elegidas, ['u-2']);
    });

    testWidgets('doble toque en la misma fila: se elige una sola vez', (tester) async {
      final hoja = Completer<void>();
      final elegidas = <String>[];
      await _montar(
        tester,
        ElegirUbicacionDelPunto(
          ubicaciones: _tres,
          alElegir: (i) {
            elegidas.add(i.ubicacion.id);
            return hoja.future;
          },
        ),
      );
      final fila = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1'));

      await tester.tap(fila);
      await tester.tap(fila);
      await tester.pump();

      expect(elegidas, ['u-1']);
      hoja.complete();
      await tester.pump();
    });

    testWidgets('dos filas seguidas antes de que termine la primera: gana la primera y no se '
        'pisa', (tester) async {
      final hoja = Completer<void>();
      final elegidas = <String>[];
      await _montar(
        tester,
        ElegirUbicacionDelPunto(
          ubicaciones: _tres,
          alElegir: (i) {
            elegidas.add(i.ubicacion.id);
            return hoja.future;
          },
        ),
      );

      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-3')));
      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
      await tester.pump();
      expect(elegidas, ['u-3']);

      hoja.complete();
      await tester.pump();
      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
      await tester.pump();
      expect(elegidas, ['u-3', 'u-1']);
    });

    testWidgets('si al elegir falla a mitad, las filas vuelven a poder tocarse', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ElegirUbicacionDelPunto(
          ubicaciones: _tres,
          alElegir: (_) async {
            llamadas++;
            throw StateError('falló');
          },
        ),
      );
      final fila = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1'));

      await tester.tap(fila);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(fila);
      await tester.pump();
      await tester.pump();

      expect(llamadas, 2);
    });

    testWidgets('volver atrás mientras se elige: al terminar no pasa nada y al reentrar se puede '
        'elegir', (tester) async {
      final hoja = Completer<void>();
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) => hoja.future),
      );
      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      hoja.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);

      final elegidas = <String>[];
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (i) => elegidas.add(i.ubicacion.id)),
      );
      await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
      await tester.pump();
      expect(elegidas, ['u-1']);
    });

    testWidgets('con una sola ubicación el título va en singular; sin ninguna no dibuja nada', (
      tester,
    ) async {
      await _montar(tester, ElegirUbicacionDelPunto(ubicaciones: [_tres.first], alElegir: (_) {}));
      expect(find.text('1 ubicación acá'), findsOneWidget);

      await _montar(tester, ElegirUbicacionDelPunto(ubicaciones: const [], alElegir: (_) {}));
      expect(find.text('Elegí cuál'), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('una baja dice «dada de baja» y una ubicación sin estado conocido, solo el tipo', (
      tester,
    ) async {
      await _montar(
        tester,
        ElegirUbicacionDelPunto(
          ubicaciones: [
            _item('b-1', baja: DateTime.utc(2026, 10, 18), estado: EstadoCasa.rechazo),
            _item('s-1', numero: '3312'),
          ],
          alElegir: (_) {},
        ),
      );

      expect(find.text('Casa · dada de baja'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Casa · Rechazó'), findsNothing);
    });

    testWidgets('una ubicación sin calle ni número se nombra «Sin dirección»', (tester) async {
      await _montar(
        tester,
        ElegirUbicacionDelPunto(
          ubicaciones: [_item('x-1', calle: null, numero: null), _item('x-2')],
          alElegir: (_) {},
        ),
      );

      expect(find.text('Sin dirección'), findsOneWidget);
    });

    testWidgets('cada fila se lee como botón con la dirección y su estado', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {}));

      final nodo = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
      expect(nodo.label, 'Grecia 3310. Casa · Cobranza pendiente');
      expect(nodo.flagsCollection.isButton, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('con 200 ubicaciones en un alto acotado se desplaza y se llega a la última', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 200; i++)
          _item('m-$i', numero: '${3000 + i}', estado: EstadoCasa.rechazo),
      ];
      final elegidas = <String>[];
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: muchas, alElegir: (i) => elegidas.add(i.ubicacion.id)),
        alto: 400,
      );

      expect(find.text('200 ubicaciones acá'), findsOneWidget);
      final ultima = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('m-199'));
      await tester.scrollUntilVisible(ultima, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(ultima);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(elegidas, ['m-199']);
    });

    testWidgets('sin alto acotado (dentro de un scroll) mide lo que miden sus filas', (
      tester,
    ) async {
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {}),
        conScroll: true,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-3')), findsOneWidget);
    });

    testWidgets('direcciones largas a 320×568 al 200 % y 300 % se parten en renglones sin '
        'desbordar', (tester) async {
      final largas = [
        _item(
          'l-1',
          calle: 'Avenida General Don José Gervasio Artigas y Doctor Luis Alberto de Herrera',
          numero: '12345 bis apartamento 1204 torre norte',
          estado: EstadoCasa.entregaYPago,
        ),
        _item('l-2', calle: 'Grecia', numero: '3310', estado: EstadoCasa.entrevistaAgendada),
      ];
      for (final escala in [2.0, 3.0]) {
        await _montar(
          tester,
          ElegirUbicacionDelPunto(ubicaciones: largas, alElegir: (_) {}),
          escala: escala,
          tamano: const Size(320, 568),
          alto: 520,
        );
        // El título a 300 % ocupa casi toda la hoja: las filas se alcanzan desplazando.
        for (final id in ['l-1', 'l-2']) {
          await tester.scrollUntilVisible(
            find.byKey(ClavesEstadosHojaCasa.filaDelPunto(id)),
            120,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(tester.takeException(), isNull, reason: 'escala $escala');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('Los tres avisos juntos', () {
    testWidgets('uno debajo del otro a 320×568 al 200 % no se pisan ni desbordan', (tester) async {
      await _montar(
        tester,
        Column(
          spacing: 12,
          children: [
            AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
            AvisoHojaCasa.lejos(metros: 650),
          ],
        ),
        escala: 2,
        tamano: const Size(320, 568),
        conScroll: true,
      );

      expect(tester.takeException(), isNull);
      final baja = tester.getRect(find.byKey(ClavesEstadosHojaCasa.avisoDadaDeBaja));
      final lejos = tester.getRect(find.byKey(ClavesEstadosHojaCasa.avisoLejos));
      expect(baja.bottom, lessThanOrEqualTo(lejos.top));
    });
  });
}
