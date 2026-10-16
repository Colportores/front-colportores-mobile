// QA ronda 1 de la vista 09 «Baja de ubicación» (HU-UBI-005, #205, PR #332). Complementa a
// `hoja_baja_test.dart` y `lista_ubicaciones_baja_test.dart` (que corren con la fuente Ahem) con lo que
// esos no miden:
//  - la matriz de estados × tamaños (360×640 y 412×915) × texto 1.0 y 2.0 con las FUENTES REALES de
//    `assets/fonts/`: sin overflow, sin texto fuera de la pantalla, tamaños de toque (Android, iOS) y
//    etiquetas; cada celda saca una captura a `.dart_tool/qa_capturas/` (nunca se commitea);
//  - el contraste de los pares de colores nuevos (aviso 09·04, «BAJA», botones rojos);
//  - los casos límite de los campos y de los avisos (solo espacios, emoji, pegado largo, saltos de línea,
//    lo tipeado tras un error, «Deshacer» en vuelo con otra reactivación, lector de pantalla).
//
// Los hallazgos de la ronda 1 (aviso con lector de pantalla, acción bajo el texto a 200 %, motivo en el
// `toString`, fila de baja sin tope) se arreglaron en el mismo PR: sus tests ya no llevan `skip`.
import 'dart:async';
import 'dart:convert';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/baja_ubicacion_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

final _hoy = DateTime.utc(2026, 10, 9, 15);
const _cobranza = CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2);

/// Una frase de 120 caracteres exactos, como la que escribe quien llena «Qué pasó».
final _motivo120 =
    '${('Se mudó al interior y la casa quedó cerrada hace meses. ' * 3).substring(0, 119)}.';

// ---------------------------------------------------------------------------------------------
// La hoja de baja (09·01 y 09·02)
// ---------------------------------------------------------------------------------------------

enum _Hoja {
  revisando,
  errorRevision,
  motivo,
  motivoElegido,
  otroLargoConTeclado,
  bloqueadaCobranza,
  bloqueadaCobranzaSinIr,
  bloqueadaAjena,
  segundaConfirmacion,
  enviando,
  fallaAlBajar,
}

class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.ubicacion, required this.salidas, required this.irALaCobranza});

  final Ubicacion ubicacion;
  final List<SalidaHojaBaja?> salidas;
  final bool irALaCobranza;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await mostrarHojaBaja(
              context,
              ubicacion: ubicacion,
              ofreceIrALaCobranza: irALaCobranza,
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

final class _Escenario {
  _Escenario(this.repo, this.pendientes);

  final RepoEdicionFalso repo;
  final PendientesFalso pendientes;
  final salidas = <SalidaHojaBaja?>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _boton => find.widgetWithText(FilledButton, TextosBaja.darDeBaja);
Finder get _campo => find.byType(TextField);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

Future<_Escenario> _hojaEn(
  WidgetTester tester,
  _Hoja estado, {
  Size tamano = telefonoChico205,
  double escala = 1,
  PendientesFalso? pendientes,
}) async {
  final pend =
      pendientes ??
      PendientesFalso(switch (estado) {
        _Hoja.bloqueadaCobranza ||
        _Hoja.bloqueadaCobranzaSinIr => const PendientesUbicacion(cobranzaPendiente: _cobranza),
        _Hoja.bloqueadaAjena => const PendientesUbicacion(tieneVentas: true),
        _Hoja.segundaConfirmacion => const PendientesUbicacion(visitasPropiasPendientes: 2),
        _ => PendientesUbicacion.ninguno,
      });
  final u = ubicacionGuardada();
  final repo = RepoEdicionFalso(u);
  if (estado == _Hoja.revisando) pend.espera = Completer<void>();
  if (estado == _Hoja.errorRevision) pend.falla = const FailurePendientesNoDisponibles();
  if (estado == _Hoja.enviando) repo.bloqueoBaja = Completer<void>();
  if (estado == _Hoja.fallaAlBajar) repo.fallaAlDarDeBaja = const FailureBajaCambioReciente();
  final e = _Escenario(repo, pend);

  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ubicacionRepositoryProvider.overrideWithValue(repo),
        relojAltaUbicacionProvider.overrideWithValue(() => _hoy),
        consultorPendientesUbicacionProvider.overrideWithValue(pend),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCaptura205,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
        ),
        home: _Anfitrion(
          ubicacion: u,
          salidas: e.salidas,
          irALaCobranza: estado != _Hoja.bloqueadaCobranzaSinIr,
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await _asentar(tester);

  switch (estado) {
    case _Hoja.motivoElegido:
      await _tocar(tester, find.text('Ya no existe'));
    case _Hoja.otroLargoConTeclado:
      await _tocar(tester, find.text('Otro'));
      await _tocar(tester, _campo);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      await tester.enterText(_campo, '$_motivo120 y algo más que sobra');
      await _asentar(tester, 5);
    case _Hoja.segundaConfirmacion || _Hoja.enviando || _Hoja.fallaAlBajar:
      await _tocar(tester, find.text('Ya no existe'));
      await _tocar(tester, _boton);
    case _:
      break;
  }
  return e;
}

// ---------------------------------------------------------------------------------------------
// La Lista con «Con bajas» y la hoja de reactivar (09·03 y 09·04)
// ---------------------------------------------------------------------------------------------

enum _Lista {
  listaConBajas,
  reactivarConMotivo,
  reactivarSinMotivo,
  reactivarMotivoLargo,
  reactivarFalla,
  reactivando,
  avisoReactivada,
  avisoNoPudimosDeshacer,
  avisoDeshecha,
}

UbicacionConResumen _baja({
  String id = 'baja-1',
  String calle = 'Av. Italia',
  String numero = '1240',
  String? motivo = 'Ya no existe',
}) => filaLista(
  id,
  calle: calle,
  numero: numero,
  hace: const Duration(days: 24),
  baja: DateTime.utc(2026, 9, 12, 15),
  motivoBaja: motivo,
);

UbicacionConResumen _activa() =>
    filaLista('casa-1', calle: 'Rivadavia', numero: '100', hace: const Duration(hours: 1));

Finder get _filaBaja => find.text('Av. Italia 1240');
Finder get _botonReactivar => find.widgetWithText(FilledButton, TextosReactivar.reactivar);
Finder get _aviso => find.text('Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.');
Finder get _deshacer => find.text('Deshacer');

Future<void> _montarLista(
  WidgetTester tester,
  RepoListaFalso repo, {
  Size tamano = telefonoChico205,
  double escala = 1,
  bool lectorDePantalla = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesLista(repo: repo),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCaptura205,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(escala),
              alwaysUse24HourFormat: true,
              accessibleNavigation: lectorDePantalla,
            ),
            child: child!,
          ),
        ),
        home: const Scaffold(body: ListaUbicacionesPage(colportorId: 'col-1', activa: true)),
      ),
    ),
  );
  await asentarLista(tester);
  await abrirHojaFiltros(tester);
  await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
  await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
  await asentarLista(tester);
  await tester.ensureVisible(botonVerUbicaciones);
  await verUbicaciones(tester);
}

Future<void> _verBaja(WidgetTester tester, [Finder? fila]) async {
  await tester.scrollUntilVisible(
    fila ?? _filaBaja,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('lista_filas')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
}

Future<void> _tocarEnLista(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: .5);
  await tester.pump();
  await tester.tap(f);
  await asentarLista(tester);
}

Future<RepoListaFalso> _listaEn(
  WidgetTester tester,
  _Lista estado, {
  Size tamano = telefonoChico205,
  double escala = 1,
}) async {
  final motivo = switch (estado) {
    _Lista.reactivarSinMotivo => null,
    _Lista.reactivarMotivoLargo => _motivo120,
    _ => 'Ya no existe',
  };
  final repo = RepoListaFalso([_activa(), _baja(motivo: motivo)]);
  await _montarLista(tester, repo, tamano: tamano, escala: escala);
  await _verBaja(tester);
  if (estado == _Lista.listaConBajas) return repo;

  await _tocarEnLista(tester, _filaBaja);
  if (estado == _Lista.reactivando) repo.bloqueoCambioDeBaja = Completer<void>();
  if (estado == _Lista.reactivarFalla) repo.fallaAlCambiarBaja = const FailureInesperado();
  switch (estado) {
    case _Lista.reactivarConMotivo || _Lista.reactivarSinMotivo || _Lista.reactivarMotivoLargo:
      break;
    case _Lista.reactivando || _Lista.reactivarFalla:
      await _tocarEnLista(tester, _botonReactivar);
    case _Lista.avisoReactivada || _Lista.avisoNoPudimosDeshacer || _Lista.avisoDeshecha:
      await _tocarEnLista(tester, _botonReactivar);
      await tester.pump(const Duration(milliseconds: 700));
      if (estado == _Lista.avisoNoPudimosDeshacer) {
        repo.fallaAlCambiarBaja = const FailureInesperado();
      }
      if (estado != _Lista.avisoReactivada) {
        await tester.tap(_deshacer);
        await tester.pump(const Duration(milliseconds: 900));
      }
    case _:
      break;
  }
  return repo;
}

// ---------------------------------------------------------------------------------------------

void main() {
  const variantes = <(Size, double)>[
    (telefonoChico205, 1.0),
    (telefonoChico205, 2.0),
    (telefonoGrande205, 1.0),
    (telefonoGrande205, 2.0),
  ];

  group('QA 09 · matriz de la hoja de baja con fuentes reales (09·01 y 09·02)', () {
    for (final (tam, escala) in variantes) {
      for (final estado in _Hoja.values) {
        testWidgets(
          'dado la hoja de baja en «${estado.name}» a ${tam.width.toInt()}×${tam.height.toInt()} '
          'con el texto ×$escala, entonces no desborda, nada se sale de la pantalla y todo lo '
          'tocable tiene tamaño y etiqueta',
          (tester) async {
            final handle = tester.ensureSemantics();
            await cargarFuentes205(tester);
            await _hojaEn(tester, estado, tamano: tam, escala: escala);
            await capturar205(tester, 'baja_${estado.name}_${tam.width.toInt()}_x$escala');

            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados205(tester, tam);
            // Con el teclado abierto la hoja se desplaza y los motivos quedan a medio ver bajo el
            // borde: `flutter_test` mide el pedazo visible y no el botón entero (falso negativo).
            if (estado != _Hoja.otroLargoConTeclado) {
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            }
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            handle.dispose();
          },
        );
      }
    }
  });

  group('QA 09 · matriz de la Lista y la hoja de reactivar con fuentes reales (09·03 y 09·04)', () {
    for (final (tam, escala) in variantes) {
      for (final estado in _Lista.values) {
        testWidgets(
          'dado «${estado.name}» a ${tam.width.toInt()}×${tam.height.toInt()} con el texto '
          '×$escala, entonces no desborda, nada se sale de la pantalla y todo lo tocable tiene '
          'tamaño y etiqueta',
          (tester) async {
            final handle = tester.ensureSemantics();
            await cargarFuentes205(tester);
            await _listaEn(tester, estado, tamano: tam, escala: escala);
            await capturar205(tester, 'lista_${estado.name}_${tam.width.toInt()}_x$escala');

            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados205(tester, tam);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            handle.dispose();
          },
        );
      }
    }
  });

  group('QA 09 · contraste de los colores de la vista (WCAG AA, 4.5:1 en texto chico)', () {
    // `textContrastGuideline` con Ahem pinta bloques y con fuentes reales da falsos negativos por el
    // antialiasing: se mide el par de colores, que es lo que decide el diseño.
    final pares = <String, (Color, Color)>{
      'texto blanco del aviso 09·04 sobre su fondo': (Colors.white, ColoresLista.tinta),
      '«Deshacer» del aviso 09·04 sobre su fondo': (const Color(0xFFC9D6EA), ColoresLista.tinta),
      '«BAJA» (blanco, 10 px) sobre su insignia': (Colors.white, ColoresColportaje.unica.gris),
      'renglón de la baja (gris) sobre el fondo de la fila de baja': (
        ColoresColportaje.unica.gris,
        ColoresLista.filaBaja,
      ),
      'dirección de la baja sobre el fondo de la fila de baja': (
        ColoresLista.grisTexto,
        ColoresLista.filaBaja,
      ),
      'texto blanco de «Dar de baja» sobre el rojo': (Colors.white, ColoresAlta.rojo),
      'aviso rojo sobre blanco': (ColoresAlta.rojo, Colors.white),
      'renglones de la hoja de reactivar (gris) sobre blanco': (ColoresAlta.gris, Colors.white),
      '«Cancelar» (azul) sobre blanco': (ColoresAlta.azul, Colors.white),
    };
    for (final MapEntry(key: nombre, value: (texto, fondo)) in pares.entries) {
      test('dado $nombre, entonces el contraste es de al menos 4.5:1', () {
        expect(contraste205(texto, fondo), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('QA 09 · textos literales de la HU y del canvas', () {
    testWidgets('09·01: título, cuerpo, motivos y botones son los del canvas', (tester) async {
      await _hojaEn(tester, _Hoja.motivo);

      for (final t in [
        '¿Dar de baja Av. Italia 1234?',
        'Deja de aparecer en el mapa y en la lista. Las visitas y ventas quedan guardadas y la '
            'podés reactivar.',
        'MOTIVO · OBLIGATORIO',
        'Ya no existe',
        'Está deshabitada',
        'No quiere visitas',
        'Otro',
        'Dar de baja',
        'Cancelar',
        'Elegí un motivo para dar de baja.',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(_habilitado(tester, _boton), isFalse, reason: 'sin motivo no se puede dar de baja');
    });

    testWidgets('09·02: la cobranza y el bloqueo ajeno dicen el texto del canvas y el de la HU', (
      tester,
    ) async {
      await _hojaEn(tester, _Hoja.bloqueadaCobranza);
      expect(find.text('Todavía no se puede dar de baja'), findsOneWidget);
      expect(
        find.text(
          r'Tiene una cobranza pendiente de $U 1.450 (2.ª cuota). Registrá el cobro antes de '
          'darla de baja.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ir a la cobranza'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('HU: el bloqueo por ventas o visitas de otro colportor y la segunda confirmación '
        'son literales', (tester) async {
      await _hojaEn(tester, _Hoja.bloqueadaAjena);
      expect(
        find.text(
          'No podés dar de baja esta casa porque tiene ventas o visitas de otro colportor. Si ya '
          'no existe, avisale a tu coordinador.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('HU: la segunda confirmación dice el literal con las visitas pendientes', (
      tester,
    ) async {
      await _hojaEn(tester, _Hoja.segundaConfirmacion);
      expect(
        find.text(
          'Esta ubicación tiene 2 visitas pendientes. Si la das de baja, no podrás registrar '
          'nuevas visitas, pero el historial se conserva.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('09·03 y 09·04: la fila, la hoja y el aviso dicen lo del canvas', (tester) async {
      await _listaEn(tester, _Lista.reactivarConMotivo);
      for (final t in [
        'Av. Italia 1240',
        'Casa · 1 espacio · Montevideo',
        'Dada de baja',
        '12/09/2026',
        'Motivo',
        'Ya no existe',
        'Reactivar',
        'Cancelar',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('Última visita'), findsNothing, reason: 'apagada (decisión P2 del #205)');

      await _tocarEnLista(tester, _botonReactivar);
      await tester.pump(const Duration(milliseconds: 700));
      expect(_aviso, findsOneWidget);
      expect(_deshacer, findsOneWidget);
    });
  });

  group('QA 09 · teclado abierto en «Otro»', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'dado el teclado abierto y el texto ×$escala en 360×640, entonces el campo que se escribe '
        'y «Dar de baja» quedan arriba del teclado',
        (tester) async {
          await cargarFuentes205(tester);
          await _hojaEn(tester, _Hoja.otroLargoConTeclado, escala: escala);

          expect(tester.takeException(), isNull);
          const arribaDelTeclado = 640.0 - 280;
          // El campo se desplaza con el cursor (a ×2 muestra sus últimos renglones): lo que importa es
          // que lo que se escribe y los botones queden arriba del teclado.
          final campo = tester.getRect(_campo);
          expect(campo.bottom, lessThanOrEqualTo(arribaDelTeclado + .5), reason: 'campo tapado');
          expect(campo.bottom, greaterThan(0), reason: 'el campo se salió por arriba');
          await tester.ensureVisible(_boton);
          await tester.pump();
          final boton = tester.getRect(_boton);
          expect(boton.bottom, lessThanOrEqualTo(arribaDelTeclado + .5), reason: 'botón tapado');
          expect(boton.top, greaterThanOrEqualTo(0));
        },
      );
    }

    testWidgets('dado «Otro» con 120 caracteres escritos y 30 de más, entonces quedan 120 y se '
        'guardan sin recortar la frase', (tester) async {
      final e = await _hojaEn(tester, _Hoja.otroLargoConTeclado);

      expect(tester.widget<TextField>(_campo).controller!.text, _motivo120);
      await _tocar(tester, _boton);
      expect(e.repo.bajas.single.motivo, _motivo120);
    });
  });

  group('QA 09 · validación del campo «Qué pasó»', () {
    testWidgets('dado «Otro» con solo espacios, cuando da de baja, entonces el motivo es «Otro»', (
      tester,
    ) async {
      final e = await _hojaEn(tester, _Hoja.motivo);
      await _tocar(tester, find.text('Otro'));
      await tester.enterText(_campo, '        ');
      await tester.pump();

      expect(_habilitado(tester, _boton), isTrue);
      await _tocar(tester, _boton);
      expect(e.repo.bajas.single.motivo, 'Otro');
    });

    testWidgets('dado «Otro» con 130 emoji, entonces el campo corta en 120 y el motivo guardado es '
        'texto válido (sin medio emoji)', (tester) async {
      final e = await _hojaEn(tester, _Hoja.motivo);
      await _tocar(tester, find.text('Otro'));
      await tester.enterText(_campo, '🏠' * 130);
      await tester.pump();
      await _tocar(tester, _boton);

      final motivo = e.repo.bajas.single.motivo!;
      expect(motivo.runes.length, 120);
      expect(utf8.decode(utf8.encode(motivo)), motivo, reason: 'sin sustitutos sueltos');
    });

    testWidgets(
      'dado «Otro» con un texto pegado de 5.000 caracteres, entonces no se traba, corta en '
      '120 y la hoja no desborda a 360×640 y texto ×2',
      (tester) async {
        final e = await _hojaEn(tester, _Hoja.motivo, escala: 2);
        await _tocar(tester, find.text('Otro'));
        await tester.enterText(_campo, 'Se mudó. ' * 560);
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(tester.widget<TextField>(_campo).controller!.text.length, 120);
        await _tocar(tester, _boton);
        expect(e.repo.bajas.single.motivo!.length, lessThanOrEqualTo(120));
      },
    );

    testWidgets('dado una falla al dar de baja con «Otro» escrito, entonces lo tipeado y el motivo '
        'elegido no se pierden y el reintento lo manda', (tester) async {
      final e = await _hojaEn(tester, _Hoja.motivo);
      await _tocar(tester, find.text('Otro'));
      await tester.enterText(_campo, 'Se mudó a Rivera');
      await tester.pump();
      e.repo.fallaAlDarDeBaja = const FailureBajaCambioReciente();
      await _tocar(tester, _boton);

      expect(find.text('✓ Otro'), findsOneWidget);
      expect(tester.widget<TextField>(_campo).controller!.text, 'Se mudó a Rivera');
      expect(_habilitado(tester, _boton), isTrue);
      expect(find.textContaining('cambió recién'), findsOneWidget);

      e.repo.fallaAlDarDeBaja = null;
      await _tocar(tester, _boton);
      expect(e.repo.bajas.last.motivo, 'Se mudó a Rivera');
      expect(e.salidas.single, isA<BajaRealizada>());
    });
  });

  group('QA 09 · Lista, reactivar y «Deshacer»', () {
    testWidgets('dado «Con bajas», entonces el contador dice cuántas bajas hay', (tester) async {
      await _montarLista(tester, RepoListaFalso([_activa(), _baja()]));

      expect(find.textContaining('· 1 baja'), findsOneWidget);
    });

    testWidgets('dado una falla al reactivar, cuando cancela y vuelve a abrir la hoja, entonces '
        'empieza de cero, sin el aviso rojo y con «Reactivar» habilitado', (tester) async {
      await _listaEn(tester, _Lista.reactivarFalla);
      expect(find.text(TextosReactivar.noPudimosReactivar), findsOneWidget);

      await _tocarEnLista(tester, find.widgetWithText(TextButton, TextosReactivar.cancelar));
      await _tocarEnLista(tester, _filaBaja);

      expect(find.text(TextosReactivar.noPudimosReactivar), findsNothing);
      expect(tester.widget<ButtonStyleButton>(_botonReactivar).onPressed, isNotNull);
    });

    testWidgets(
      'dado un «Deshacer» en vuelo, cuando se reactiva otra baja, entonces el aviso de la '
      'segunda y su «Deshacer» no se pierden',
      (tester) async {
        final repo = RepoListaFalso([
          _activa(),
          _baja(),
          _baja(id: 'baja-2', calle: 'Gral. Flores', numero: '1500', motivo: 'Está deshabitada'),
        ]);
        await _montarLista(tester, repo);
        await _verBaja(tester);
        await _tocarEnLista(tester, _filaBaja);
        await _tocarEnLista(tester, _botonReactivar);
        await tester.pump(const Duration(milliseconds: 700));

        // «Deshacer» de la primera queda esperando al repositorio.
        final espera = Completer<void>();
        repo.bloqueoCambioDeBaja = espera;
        await tester.tap(_deshacer);
        await tester.pump(const Duration(milliseconds: 100));
        repo.bloqueoCambioDeBaja = null;

        await _verBaja(tester, find.text('Gral. Flores 1500'));
        await _tocarEnLista(tester, find.text('Gral. Flores 1500'));
        await _tocarEnLista(tester, _botonReactivar);
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          find.text('Gral. Flores 1500 reactivada. Vuelve a aparecer en el mapa.'),
          findsOneWidget,
        );

        espera.complete();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(
          find.text('Gral. Flores 1500 reactivada. Vuelve a aparecer en el mapa.'),
          findsOneWidget,
          reason: 'el aviso de la segunda sigue a la vista',
        );
        await tester.tap(_deshacer);
        await tester.pump(const Duration(milliseconds: 900));
        final bajas = repo.cambiosDeBaja.where((c) => c.baja).map((c) => c.id).toList();
        expect(bajas, containsAll(['baja-1', 'baja-2']), reason: 'las dos se pudieron deshacer');
      },
    );

    testWidgets('dado el lector de pantalla encendido, cuando reactiva, entonces «Deshacer» sigue '
        'a la mano pasados los 8 s (WCAG 2.2.1: sin tiempo límite para quien navega con lector)', (
      tester,
    ) async {
      final repo = RepoListaFalso([_activa(), _baja()]);
      await _montarLista(tester, repo, lectorDePantalla: true);
      await _verBaja(tester);
      await _tocarEnLista(tester, _filaBaja);
      await _tocarEnLista(tester, _botonReactivar);

      await tester.pump(const Duration(seconds: 9));
      await asentarLista(tester);

      expect(_deshacer, findsOneWidget);
    });

    testWidgets(
      'dado el texto ×2 en 360×640, cuando reactiva, entonces el aviso 09·04 no ocupa más de '
      'un tercio de la pantalla (ni parte «reactivada» a mitad de palabra)',
      (tester) async {
        await cargarFuentes205(tester);
        await _listaEn(tester, _Lista.avisoReactivada, escala: 2);

        expect(tester.getSize(find.byType(SnackBar)).height, lessThanOrEqualTo(640 / 3));
      },
    );

    testWidgets('dado una baja con saltos de línea en el motivo (se pegan en «Qué pasó»), entonces '
        'la fila de la Lista no crece más que una de dos renglones', (tester) async {
      final repo = RepoListaFalso([_baja(motivo: 'Se mudó\n\n\n\n\n\n\n\n\n\nal interior')]);
      await _montarLista(tester, repo);
      await _verBaja(tester);

      // Una fila normal (dirección + renglón) mide unos 70 px.
      expect(tester.getSize(find.byType(FilaUbicacionLista)).height, lessThanOrEqualTo(100));
    });
  });

  group('QA 09 · privacidad', () {
    test(
      'dado el motivo de una baja (texto libre), entonces no sale en el toString de la fila de la '
      'Lista',
      () {
        final fila = _baja(motivo: 'Se mudó a Rivera, tel 099123456');
        expect(fila.toString(), isNot(contains('Rivera')));
        expect(fila.toString(), isNot(contains('099123456')));
      },
    );

    test('dado el motivo de una baja, entonces no sale en el toString de los parámetros del caso '
        'de uso', () {
      final params = DarDeBajaUbicacionParams(
        id: 'u-1',
        baseUpdatedAt: _hoy,
        motivo: 'Se mudó a Rivera, tel 099123456',
      );
      expect(params.toString(), isNot(contains('Rivera')));
    });
  });
}
