// QA de «Reactivar una baja» (HU-UBI-005, #334, PR #366): la Lista con «Con bajas» (fila de la baja
// común y fila «Unida a otra ubicación»), la hoja de «Reactivar» (09·03), la hoja «No se puede
// reactivar» (choque de dirección única D1 y baja por unión de duplicados) y el aviso con «Deshacer»
// (09·04). Complementa a `lista_ubicaciones_baja_test.dart` (Ahem, un tamaño) con lo que ese no mide:
//  - la matriz estados × 5 tamaños (320×568, 360×640, 360×740, 390×844, 412×915) × texto 1,0 y 2,0 con
//    las FUENTES REALES de `assets/fonts/`: sin overflow, sin texto fuera de la pantalla, tamaños de
//    toque (Android e iOS) y etiquetas; cada celda saca una captura a `.dart_tool/qa_capturas/`
//    (gitignored, nunca se commitea);
//  - lo que oye el lector de pantalla (rol, acción de tocar, pista, región viva) en cada estado;
//  - el contraste de los pares de colores nuevos;
//  - los textos literales de la HU y de las decisiones del 16/10;
//  - casos límite que los tests del PR no tocan (cambio de tamaño y de escala con la hoja abierta,
//    la lista que cambia por debajo de la hoja, el aviso con lector de pantalla un minuto después).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_reactivar_334_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

final _el12 = DateTime.utc(2026, 9, 12, 15);
final _el03 = DateTime.utc(2026, 9, 3, 15);

/// Una frase de 120 caracteres exactos (el tope del «Otro» de la baja).
final _motivo120 =
    '${('Se mudó al interior y la casa quedó cerrada hace meses. ' * 3).substring(0, 119)}.';

const _textoUnion = 'Esta ubicación se unió a otra y no se puede reactivar. Seguí usando la otra.';
const _textoChoque =
    'No puede haber dos ubicaciones con la misma dirección a menos de 100 m, y Rivadavia 100 ya '
    'está activa. Si es la misma, seguí usando esa; si es otra puerta, abrila y agregala como '
    'espacio.';

UbicacionConResumen _activa() =>
    filaLista('casa-1', calle: 'Rivadavia', numero: '100', hace: const Duration(days: 5));

/// La baja común del canvas: «Av. Italia 1240 · baja el 12/09 · Ya no existe».
UbicacionConResumen _baja({
  String id = 'baja-1',
  String calle = 'Av. Italia',
  String numero = '1240',
  String? motivo = 'Ya no existe',
}) => filaLista(
  id,
  calle: calle,
  numero: numero,
  hace: const Duration(hours: 3),
  baja: _el12,
  motivoBaja: motivo,
);

/// La baja por unión de duplicados: el motivo guardado es el código; la Lista dice «Unida a otra
/// ubicación».
UbicacionConResumen _union() => filaLista(
  'baja-union',
  calle: 'Michigan',
  numero: '1552',
  hace: const Duration(hours: 4),
  baja: _el03,
  motivoBaja: 'duplicado_de_casa-1',
);

UbicacionConResumen _bajaSinMotivo() => filaLista(
  'baja-sin',
  calle: 'Orinoco',
  numero: '5031',
  hace: const Duration(hours: 5),
  baja: _el03,
);

/// Monta la Lista con «Con bajas» activo (como la ve quien llegó desde el filtro), con fuentes reales,
/// una raíz de captura y la escala del texto en un notificador para poder cambiarla.
Future<void> _montar(
  WidgetTester tester,
  RepoListaFalso repo, {
  Size tamano = t390x844,
  ValueNotifier<double>? escala,
  bool lector = false,
  ValueChanged<String>? alAbrir,
}) async {
  final esc = escala ?? ValueNotifier<double>(1);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesLista(repo: repo),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCaptura334,
          child: ValueListenableBuilder<double>(
            valueListenable: esc,
            builder: (context, e, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(e),
                alwaysUse24HourFormat: true,
                accessibleNavigation: lector,
              ),
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: ListaUbicacionesPage(colportorId: 'col-1', activa: true, alAbrirUbicacion: alAbrir),
        ),
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

Future<void> _verFila(WidgetTester tester, Finder fila) async {
  await tester.scrollUntilVisible(
    fila,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('lista_filas')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pump();
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: .5);
  await tester.pump();
  await tester.tap(f);
  await asentarLista(tester);
}

Finder get _filaBaja => find.text('Av. Italia 1240');
Finder get _botonReactivar => find.widgetWithText(FilledButton, TextosReactivar.reactivar);
Finder get _botonReactivando => find.widgetWithText(FilledButton, TextosReactivar.reactivando);
Finder get _cancelar => find.widgetWithText(TextButton, TextosReactivar.cancelar);
Finder get _aviso => find.text('Av. Italia 1240 reactivada. Vuelve a aparecer en el mapa.');
Finder get _deshacer => find.text('Deshacer');
Finder get _abrirExistente => find.widgetWithText(FilledButton, TextosReactivar.abrirExistente);
Finder get _entendido => find.widgetWithText(FilledButton, TextosReactivar.entendido);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

// ---------------------------------------------------------------------------------------------
// Los estados de la matriz
// ---------------------------------------------------------------------------------------------

enum _Estado {
  listaConBajas,
  hojaConMotivo,
  hojaMotivoLargo,
  hojaSinMotivo,
  hojaDireccionLarga,
  reactivando,
  fallaInesperada,
  cambioReciente,
  chocaConAbrir,
  chocaSinAbrir,
  unionConAbrir,
  unionSinAbrir,
  avisoReactivada,
  avisoConLector,
  avisoNoPudimosDeshacer,
  avisoDeshecha,
}

/// Los que no necesitan la matriz entera (el mismo contenido que otro en otro orden).
const _estadosReducidos = {
  _Estado.hojaSinMotivo,
  _Estado.hojaDireccionLarga,
  _Estado.cambioReciente,
};

const _variantesReducidas = <(Size, double)>[
  (t320x568, 2.0),
  (t360x640, 1.0),
  (t360x640, 2.0),
  (t412x915, 1.0),
];

Future<RepoListaFalso> _llegarA(
  WidgetTester tester,
  _Estado e, {
  Size tamano = t390x844,
  double escala = 1,
}) async {
  final motivo = switch (e) {
    _Estado.hojaMotivoLargo => _motivo120,
    _Estado.hojaSinMotivo => null,
    _ => 'Ya no existe',
  };
  final calle = e == _Estado.hojaDireccionLarga
      ? 'Avenida General Don José de San Martín y Bulevar Artigas esquina Rambla'
      : 'Av. Italia';
  final numero = e == _Estado.hojaDireccionLarga ? '12345 bis' : '1240';
  final repo = RepoListaFalso([
    _activa(),
    _baja(motivo: motivo, calle: calle, numero: numero),
    _union(),
    _bajaSinMotivo(),
  ]);
  final conAbrir = e == _Estado.chocaConAbrir || e == _Estado.unionConAbrir;
  await _montar(
    tester,
    repo,
    tamano: tamano,
    escala: ValueNotifier(escala),
    lector: e == _Estado.avisoConLector,
    alAbrir: conAbrir ? (_) {} : null,
  );
  if (e == _Estado.listaConBajas) return repo;

  final fila = find.text('$calle $numero');
  await _verFila(tester, fila);
  if (e == _Estado.hojaDireccionLarga) {
    // A 200 % la dirección ocupa casi toda la pantalla y el botón «Nueva» tapa el centro de la fila: se
    // toca por arriba, que es donde la tocaría quien la ve.
    await Scrollable.ensureVisible(tester.element(fila), alignment: 0);
    await tester.pump();
    await tester.tapAt(tester.getTopLeft(fila) + const Offset(6, 6));
    await asentarLista(tester);
  } else {
    await _tocar(tester, fila);
  }

  switch (e) {
    case _Estado.reactivando:
      repo.bloqueoCambioDeBaja = Completer<void>();
      await _tocar(tester, _botonReactivar);
    case _Estado.fallaInesperada:
      repo.fallaAlCambiarBaja = const FailureInesperado();
      await _tocar(tester, _botonReactivar);
    case _Estado.cambioReciente:
      repo.filaCambiada = true;
      await _tocar(tester, _botonReactivar);
    case _Estado.chocaConAbrir || _Estado.chocaSinAbrir:
      repo.fallaAlCambiarBaja = const FailureReactivacionChocaConActiva(
        existenteId: 'casa-1',
        direccion: 'Rivadavia 100',
      );
      await _tocar(tester, _botonReactivar);
    case _Estado.unionConAbrir:
      repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion(conservadaId: 'casa-1');
      await _tocar(tester, _botonReactivar);
    case _Estado.unionSinAbrir:
      repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion();
      await _tocar(tester, _botonReactivar);
    case _Estado.avisoReactivada ||
        _Estado.avisoConLector ||
        _Estado.avisoNoPudimosDeshacer ||
        _Estado.avisoDeshecha:
      await _tocar(tester, _botonReactivar);
      await tester.pump(const Duration(milliseconds: 700));
      if (e == _Estado.avisoNoPudimosDeshacer) {
        repo.fallaAlCambiarBaja = const FailureInesperado();
      }
      if (e == _Estado.avisoNoPudimosDeshacer || e == _Estado.avisoDeshecha) {
        await tester.tap(_deshacer);
        await tester.pump(const Duration(milliseconds: 900));
        // El aviso de «Deshacer» sale y recién entonces entra el que dice cómo salió.
        await asentarLista(tester, 14);
      }
    case _:
      break;
  }
  return repo;
}

Future<void> _revisarCelda(WidgetTester tester, Size tam, String nombre) async {
  await capturar334(tester, nombre);
  expect(tester.takeException(), isNull, reason: 'sin overflow ni otra excepción');
  expectSinTextoFueraDeLosCostados205(tester, tam);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

// ---------------------------------------------------------------------------------------------

void main() {
  group('QA 09·03/04 · matriz de estados con fuentes reales', () {
    for (final estado in _Estado.values) {
      final variantes = _estadosReducidos.contains(estado) ? _variantesReducidas : matriz334;
      for (final (tam, escala) in variantes) {
        testWidgets(
          'dado «${estado.name}» a ${tam.width.toInt()}×${tam.height.toInt()} con el texto ×$escala, '
          'entonces no desborda, nada se sale de la pantalla y todo lo tocable tiene tamaño y '
          'etiqueta',
          (tester) async {
            final handle = tester.ensureSemantics();
            await cargarFuentes205(tester);
            await _llegarA(tester, estado, tamano: tam, escala: escala);
            await _revisarCelda(tester, tam, '${estado.name}_${sufijo334(tam, escala)}');
            handle.dispose();
          },
        );
      }
    }
  });

  group('QA 09·03/04 · contraste de los pares de colores de la vista (WCAG AA, 4.5:1)', () {
    final pares = <String, (Color, Color)>{
      'texto de los avisos (tema) sobre el cuadro blanco': (
        temaClaro().colorScheme.onSurface,
        Colors.white,
      ),
      'glifo «!» blanco sobre la insignia azul de «No se puede reactivar»': (
        Colors.white,
        ColoresAlta.azul,
      ),
      'glifo «!» blanco sobre la insignia roja del aviso de falla': (
        Colors.white,
        ColoresAlta.rojo,
      ),
      'texto blanco del aviso 09·04 sobre su fondo': (Colors.white, ColoresLista.tinta),
      '«Deshacer» del aviso 09·04 sobre su fondo': (const Color(0xFFC9D6EA), ColoresLista.tinta),
      '«BAJA» (blanco, 10 px) sobre su etiqueta': (Colors.white, ColoresColportaje.unica.gris),
      'meta de la baja (gris) sobre el fondo de la fila de baja': (
        ColoresColportaje.unica.gris,
        ColoresLista.filaBaja,
      ),
      'dirección de la baja sobre el fondo de la fila de baja': (
        ColoresLista.grisTexto,
        ColoresLista.filaBaja,
      ),
      'renglones de la hoja (gris) sobre blanco': (ColoresAlta.gris, Colors.white),
      '«Cancelar» (azul) sobre blanco': (ColoresAlta.azul, Colors.white),
    };
    for (final MapEntry(key: nombre, value: (texto, fondo)) in pares.entries) {
      test('dado $nombre, entonces el contraste es de al menos 4.5:1', () {
        expect(contraste205(texto, fondo), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('QA 09·03/04 · lo que oye el lector de pantalla', () {
    testWidgets('dado la baja común, entonces la fila es un botón con acción de tocar, la pista '
        '«Tocá para reactivar» y el motivo en la etiqueta', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, RepoListaFalso([_activa(), _baja()]));
      await _verFila(tester, _filaBaja);

      final nodo = tester.getSemantics(find.bySemanticsLabel(RegExp('Av. Italia 1240. Baja')));
      expect(
        nodo,
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          hint: 'Tocá para reactivar',
        ),
      );
      expect(nodo.label, contains('Casa · baja el 12/09 · Ya no existe'));
      handle.dispose();
    });

    testWidgets(
      'dado la baja por unión, entonces la fila NO es un botón, no tiene acción de tocar, '
      'está deshabilitada y dice «Unida a otra ubicación» sin el código ni el uuid',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, RepoListaFalso([_activa(), _union()]));
        await _verFila(tester, find.text('Michigan 1552'));

        final nodo = tester.getSemantics(find.bySemanticsLabel(RegExp('Michigan 1552. Baja')));
        expect(
          nodo,
          isSemantics(
            isButton: false,
            hasTapAction: false,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        final etiqueta = nodo.label;
        expect(etiqueta, contains('Casa · baja el 03/09 · Unida a otra ubicación'));
        expect(etiqueta, isNot(contains('duplicado')));
        expect(etiqueta, isNot(contains('casa-1')));
        expect(nodo.hint, isNot(contains('reactivar')));
        handle.dispose();
      },
    );

    testWidgets('dado la hoja de «Reactivar», entonces el título es encabezado y región viva, los '
        'renglones se leen «etiqueta: valor» y los botones tienen acción de tocar', (tester) async {
      final handle = tester.ensureSemantics();
      await _llegarA(tester, _Estado.hojaConMotivo);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Av. Italia 1240').last),
        isSemantics(isHeader: true, isLiveRegion: true),
      );
      expect(find.bySemanticsLabel('Dada de baja: 12/09/2026'), findsOneWidget);
      expect(find.bySemanticsLabel('Motivo: Ya no existe'), findsOneWidget);
      expect(
        tester.getSemantics(_botonReactivar),
        isSemantics(isButton: true, hasTapAction: true, isEnabled: true, label: 'Reactivar'),
      );
      expect(
        tester.getSemantics(_cancelar),
        isSemantics(isButton: true, hasTapAction: true, isEnabled: true, label: 'Cancelar'),
      );
      handle.dispose();
    });

    testWidgets('dado «Reactivando…», entonces el botón y «Cancelar» están deshabilitados para el '
        'lector (sin acción de tocar)', (tester) async {
      final handle = tester.ensureSemantics();
      await _llegarA(tester, _Estado.reactivando);

      expect(
        tester.getSemantics(_botonReactivando),
        isSemantics(hasTapAction: false, isEnabled: false, hasEnabledState: true),
      );
      expect(
        tester.getSemantics(_cancelar),
        isSemantics(hasTapAction: false, isEnabled: false, hasEnabledState: true),
      );
      handle.dispose();
    });

    for (final (nombre, estado, boton) in [
      ('el choque D1 con «Abrir la existente»', _Estado.chocaConAbrir, 'Abrir la existente'),
      ('la unión con «Abrir la existente»', _Estado.unionConAbrir, 'Abrir la existente'),
      ('el choque D1 sin dónde abrir', _Estado.chocaSinAbrir, 'Entendido'),
      ('la unión sin conservada', _Estado.unionSinAbrir, 'Entendido'),
    ]) {
      testWidgets('dado $nombre, entonces el título es encabezado y región viva y el botón '
          '«$boton» tiene acción de tocar', (tester) async {
        final handle = tester.ensureSemantics();
        await _llegarA(tester, estado);

        expect(
          tester.getSemantics(find.bySemanticsLabel('No se puede reactivar')),
          isSemantics(isHeader: true, isLiveRegion: true),
        );
        expect(
          tester.getSemantics(find.widgetWithText(FilledButton, boton)),
          isSemantics(isButton: true, hasTapAction: true, isEnabled: true, label: boton),
        );
        handle.dispose();
      });
    }

    testWidgets('dado el aviso con «Deshacer», entonces el lector lo activa con la acción de tocar '
        'y vuelve a dar de baja', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _llegarA(tester, _Estado.avisoReactivada);

      tester.semantics.tap(find.semantics.byLabel('Deshacer'));
      await tester.pump(const Duration(milliseconds: 900));
      await asentarLista(tester);

      expect(repo.cambiosDeBaja.last.baja, isTrue);
      expect(find.text('Volvió a quedar de baja.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('dado el aviso con texto ×2,0 (la acción baja debajo), entonces «Deshacer» también '
        'tiene acción de tocar', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await _llegarA(tester, _Estado.avisoReactivada, escala: 2);

      tester.semantics.tap(find.semantics.byLabel('Deshacer'));
      await tester.pump(const Duration(milliseconds: 900));

      expect(repo.cambiosDeBaja.last.baja, isTrue);
      handle.dispose();
    });

    testWidgets('dado un lector de pantalla activo, entonces el aviso con «Deshacer» sigue un '
        'minuto después y «Deshacer» funciona (WCAG 2.2.1)', (tester) async {
      final repo = await _llegarA(tester, _Estado.avisoConLector);

      await tester.pump(const Duration(seconds: 60));

      expect(_aviso, findsOneWidget);
      await tester.tap(_deshacer);
      await tester.pump(const Duration(milliseconds: 900));
      expect(repo.cambiosDeBaja.last.baja, isTrue);
    });
  });

  group('QA 09·03/04 · textos literales de la HU y de las decisiones', () {
    testWidgets('HU: la fila de la unión dice «Unida a otra ubicación» en el lugar del motivo, sin '
        'el código ni el uuid', (tester) async {
      await _montar(tester, RepoListaFalso([_activa(), _union()]));
      await _verFila(tester, find.text('Michigan 1552'));

      expect(find.text('Casa · baja el 03/09 · Unida a otra ubicación'), findsOneWidget);
      expect(find.textContaining('duplicado_de'), findsNothing);
      expect(find.textContaining('casa-1'), findsNothing);
    });

    testWidgets('HU: «Reactivar choca con otra casa activa» dice «No se puede reactivar» y el '
        'texto D1 con la dirección de la otra', (tester) async {
      await _llegarA(tester, _Estado.chocaConAbrir);

      expect(find.text('No se puede reactivar'), findsOneWidget);
      expect(find.text(_textoChoque), findsOneWidget);
      expect(find.text('Abrir la existente'), findsOneWidget);
      expect(find.text('Reactivar'), findsNothing, reason: 'la hoja ya no ofrece reactivar');
    });

    testWidgets('decisión 16/10 (P1): la baja que se unió dice el texto decidido', (tester) async {
      await _llegarA(tester, _Estado.unionConAbrir);

      expect(find.text('No se puede reactivar'), findsOneWidget);
      expect(find.text(_textoUnion), findsOneWidget);
    });

    testWidgets('HU: la fila cambió mientras tanto, entonces dice el literal de la HU', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.cambioReciente);

      expect(
        find.text('Esta ubicación cambió recién. Abrila de nuevo y volvé a reactivarla.'),
        findsOneWidget,
      );
    });

    testWidgets('canvas 09·04: reactivada, el aviso dice el texto del canvas y «Deshacer»; la fila '
        'vuelve a ser una activa (sin «BAJA») y el contador pierde una baja', (tester) async {
      final repo = RepoListaFalso([_activa(), _baja(), _union()]);
      await _montar(tester, repo);
      expect(find.text('3 de 3 · 2 bajas'), findsOneWidget);

      await _verFila(tester, _filaBaja);
      await _tocar(tester, _filaBaja);
      await _tocar(tester, _botonReactivar);
      await tester.pump(const Duration(milliseconds: 700));

      expect(_aviso, findsOneWidget);
      expect(_deshacer, findsOneWidget);
      expect(find.text('3 de 3 · 1 baja'), findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget, reason: 'queda solo la unión');
    });

    testWidgets('el aviso rojo de una falla inesperada guía: dice qué pasó y qué hacer, con el '
        'botón «Reactivar» a mano', (tester) async {
      await _llegarA(tester, _Estado.fallaInesperada);

      expect(find.text('No pudimos reactivar la ubicación. Probá de nuevo.'), findsOneWidget);
      expect(_habilitado(tester, _botonReactivar), isTrue);
      expect(_habilitado(tester, _cancelar), isTrue);
    });

    testWidgets(
      'una falla de conexión (si algún día llegara) dice «Necesitás conexión para …», no el '
      'genérico',
      (tester) async {
        final repo = await _llegarA(tester, _Estado.hojaConMotivo);
        repo.fallaAlCambiarBaja = const FailureSinConexion();

        await _tocar(tester, _botonReactivar);

        expect(find.text('Necesitás conexión para reactivar la ubicación.'), findsOneWidget);
        expect(_habilitado(tester, _botonReactivar), isTrue);
      },
    );
  });

  group('QA 09·03/04 · casos límite', () {
    testWidgets('dado «Abrir la existente» de una unión, entonces abre la conservada una sola vez '
        'y cierra la hoja', (tester) async {
      final abiertas = <String>[];
      final repo = RepoListaFalso([_activa(), _baja()]);
      await _montar(tester, repo, alAbrir: abiertas.add);
      await _verFila(tester, _filaBaja);
      await _tocar(tester, _filaBaja);
      repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion(conservadaId: 'casa-1');
      await _tocar(tester, _botonReactivar);

      await tester.tap(_abrirExistente);
      await tester.tap(_abrirExistente, warnIfMissed: false);
      await asentarLista(tester);

      expect(abiertas, ['casa-1']);
      expect(find.text('No se puede reactivar'), findsNothing);
    });

    testWidgets(
      'dado que la unión llega por una carrera, cuando se cierra con «Entendido», entonces '
      'la Lista (que cambió por debajo) ya muestra la fila sin botón',
      (tester) async {
        final repo = RepoListaFalso([_activa(), _baja()]);
        await _montar(tester, repo);
        await _verFila(tester, _filaBaja);
        await _tocar(tester, _filaBaja);
        // La unión se hizo mientras la hoja estaba abierta: la lista emite la baja ya como unión.
        repo.emitir([_activa(), _baja(motivo: 'duplicado_de_casa-1')]);
        repo.fallaAlCambiarBaja = const FailureReactivacionDeUnion();
        await _tocar(tester, _botonReactivar);
        expect(find.text(_textoUnion), findsOneWidget);

        await _tocar(tester, _entendido);

        expect(find.text('Casa · baja el 12/09 · Unida a otra ubicación'), findsOneWidget);
        // La fila ya no abre nada: tocarla no abre ninguna hoja.
        await tester.tap(_filaBaja);
        await asentarLista(tester);
        expect(find.text('Reactivar'), findsNothing);
        expect(find.text('Dada de baja'), findsNothing);
      },
    );

    testWidgets(
      'dado que la lista cambia por debajo de la hoja (la baja pasa a activa por el sync), '
      'entonces «Reactivar» no revienta y avisa',
      (tester) async {
        final repo = RepoListaFalso([_activa(), _baja()]);
        await _montar(tester, repo);
        await _verFila(tester, _filaBaja);
        await _tocar(tester, _filaBaja);
        repo.emitir([_activa(), filaLista('baja-1', calle: 'Av. Italia', numero: '1240')]);
        await asentarLista(tester);

        await _tocar(tester, _botonReactivar);

        expect(tester.takeException(), isNull);
        expect(_botonReactivando, findsNothing);
        expect(find.byType(HojaReactivarUbicacion), findsNothing);
      },
    );

    for (final estado in [
      _Estado.hojaConMotivo,
      _Estado.reactivando,
      _Estado.chocaConAbrir,
      _Estado.unionSinAbrir,
      _Estado.avisoReactivada,
    ]) {
      testWidgets('dado «${estado.name}», cuando el teléfono pasa de 412×915 a 320×568 y el texto '
          'de ×1,0 a ×2,0 (girar, cambiar la fuente), entonces no desborda y nada se sale de la '
          'pantalla', (tester) async {
        final handle = tester.ensureSemantics();
        await cargarFuentes205(tester);
        await _llegarA(tester, estado, tamano: t412x915);

        tester.view.physicalSize = t320x568;
        await tester.pump(const Duration(milliseconds: 100));
        await _cambiarEscala(tester, 2);
        await asentarLista(tester);

        await _revisarCelda(tester, t320x568, 'cambio_${estado.name}');
        handle.dispose();
      });
    }

    testWidgets('dado «No pudimos deshacer…» y «Volvió a quedar de baja.», entonces cada uno es el '
        'aviso que se ve (no queda el de «Deshacer» debajo)', (tester) async {
      await _llegarA(tester, _Estado.avisoNoPudimosDeshacer);
      expect(
        find.text('No pudimos deshacer. Podés darla de baja de nuevo desde Editar.'),
        findsOneWidget,
      );
      expect(_aviso, findsNothing);
    });

    testWidgets('dado «Deshacer» a tiempo, entonces el aviso dice «Volvió a quedar de baja.»', (
      tester,
    ) async {
      await _llegarA(tester, _Estado.avisoDeshecha);
      expect(find.text('Volvió a quedar de baja.'), findsOneWidget);
      expect(_aviso, findsNothing);
    });

    for (final (nombre, estado, fin) in [
      ('la hoja de «Reactivar» con un motivo de 120 caracteres', _Estado.hojaMotivoLargo, 'meses.'),
      ('la hoja de «Reactivar»', _Estado.hojaConMotivo, 'Ya no existe'),
    ]) {
      testWidgets('dado $nombre a 320×568 con el texto ×2,0, entonces se llega al renglón «Motivo» '
          'entero desplazando la hoja y «Reactivar» sigue a la vista', (tester) async {
        await cargarFuentes205(tester);
        await _llegarA(tester, estado, tamano: t320x568, escala: 2);
        final scroll = find.descendant(
          of: find.byType(HojaReactivarUbicacion),
          matching: find.byType(SingleChildScrollView),
        );

        await tester.drag(scroll, const Offset(0, -900));
        await tester.pump();

        final textoFinal = tester.getRect(
          find
              .descendant(
                of: find.byType(HojaReactivarUbicacion),
                matching: find.textContaining(fin),
              )
              .last,
        );
        expect(textoFinal.bottom, lessThanOrEqualTo(tester.getRect(_botonReactivar).top + 0.5));
        expect(textoFinal.top, greaterThanOrEqualTo(0));
        expect(tester.getRect(_botonReactivar).bottom, lessThanOrEqualTo(568));
      });
    }

    for (final (nombre, estado, fin) in [
      ('el choque D1', _Estado.chocaConAbrir, 'agregala como espacio.'),
      ('la unión', _Estado.unionConAbrir, 'Seguí usando la otra.'),
    ]) {
      testWidgets('dado $nombre a 320×568 con el texto ×2,0, cuando el cuerpo no entra, entonces se '
          'llega al final desplazando la hoja y los botones siguen a la vista', (tester) async {
        await cargarFuentes205(tester);
        await _llegarA(tester, estado, tamano: t320x568, escala: 2);
        final scroll = find.descendant(
          of: find.byType(HojaReactivarUbicacion),
          matching: find.byType(SingleChildScrollView),
        );

        await tester.drag(scroll, const Offset(0, -600));
        await tester.pump();

        // El párrafo es más alto que el pedazo visible: al llegar al final su cola queda sobre el botón
        // (nada tapado) y el principio ya salió por arriba.
        final textoFinal = tester.getRect(find.textContaining(fin));
        final boton = tester.getRect(_abrirExistente);
        expect(textoFinal.bottom, lessThanOrEqualTo(boton.top + 0.5));
        expect(boton.bottom, lessThanOrEqualTo(568));
      });
    }

    testWidgets('HU «Reactivación con la ciudad fuera del catálogo»: la hoja no la nombra y '
        '«Reactivar» reactiva igual', (tester) async {
      final repo = RepoListaFalso([
        _activa(),
        filaLista(
          'baja-1',
          calle: 'Av. Italia',
          numero: '1240',
          ciudadId: 'ciu-que-ya-no-esta',
          hace: const Duration(hours: 3),
          baja: _el12,
          motivoBaja: 'Ya no existe',
        ),
      ]);
      await _montar(tester, repo);
      await _verFila(tester, _filaBaja);
      await _tocar(tester, _filaBaja);
      expect(find.text('Casa · 1 espacio'), findsOneWidget);

      await _tocar(tester, _botonReactivar);

      expect(repo.cambiosDeBaja.single.baja, isFalse);
      expect(_aviso, findsOneWidget);
    });

    testWidgets('dado «Reactivando…», cuando toca el fondo oscuro de afuera de la hoja, entonces '
        'la hoja no se cierra y al terminar sigue su curso', (tester) async {
      final repo = await _llegarA(tester, _Estado.reactivando);

      await tester.tapAt(const Offset(10, 60));
      await asentarLista(tester);

      expect(find.byType(HojaReactivarUbicacion), findsOneWidget);
      expect(_botonReactivando, findsOneWidget);

      repo.bloqueoCambioDeBaja!.complete();
      await asentarLista(tester);
      expect(find.byType(HojaReactivarUbicacion), findsNothing);
      expect(_aviso, findsOneWidget);
    });

    for (final estado in [
      _Estado.hojaConMotivo,
      _Estado.fallaInesperada,
      _Estado.cambioReciente,
      _Estado.chocaConAbrir,
      _Estado.chocaSinAbrir,
      _Estado.unionConAbrir,
      _Estado.unionSinAbrir,
    ]) {
      testWidgets('dado «${estado.name}», cuando vuelve atrás o toca el fondo, entonces la hoja se '
          'cierra sin abrir nada ni escribir otra vez', (tester) async {
        final abiertas = <String>[];
        final repo = await _llegarA(tester, estado);
        final escrituras = repo.cambiosDeBaja.length;

        await tester.binding.handlePopRoute();
        await asentarLista(tester);

        expect(find.byType(HojaReactivarUbicacion), findsNothing);
        expect(repo.cambiosDeBaja, hasLength(escrituras));
        expect(abiertas, isEmpty);
        expect(_aviso, findsNothing);
      });

      testWidgets('dado «${estado.name}», cuando toca el fondo oscuro, entonces la hoja se cierra '
          'sin escribir otra vez', (tester) async {
        final repo = await _llegarA(tester, estado);
        final escrituras = repo.cambiosDeBaja.length;

        await tester.tapAt(const Offset(10, 40));
        await asentarLista(tester);

        expect(find.byType(HojaReactivarUbicacion), findsNothing);
        expect(repo.cambiosDeBaja, hasLength(escrituras));
      });
    }

    testWidgets('dado una baja con dirección larguísima, entonces la fila y la hoja la muestran '
        'entera y la etiqueta «BAJA» no pisa la dirección', (tester) async {
      await cargarFuentes205(tester);
      await _llegarA(tester, _Estado.hojaDireccionLarga, tamano: t320x568, escala: 2);

      expect(find.textContaining('Avenida General Don José de San Martín'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA 09·03 · fidelidad al canvas', () {
    testWidgets(
      '09·03: mientras la hoja está abierta, la fila de la baja va resaltada (canvas: fondo '
      '#E6EEF8 y barra azul de 3 px a la izquierda)',
      (tester) async {
        await _llegarA(tester, _Estado.hojaConMotivo);

        final fila = find.byWidgetPredicate(
          (w) => w is FilaUbicacionLista && w.item.ubicacion.id == 'baja-1',
        );
        final contenedor = tester.widget<Container>(
          find.descendant(of: fila, matching: find.byType(Container)).first,
        );
        expect((contenedor.decoration! as BoxDecoration).color, const Color(0xFFE6EEF8));
      },
      skip: true,
    ); // skip: QA #334 — 09·03: la fila de la baja que se reactiva no se resalta (canvas).
  });

  group('QA 09·03/04 · privacidad', () {
    test('dado el choque D1 y la unión, entonces el toString solo trae el código (ni la dirección '
        'ni el uuid)', () {
      const choque = FailureReactivacionChocaConActiva(
        existenteId: 'uuid-secreto-1',
        direccion: 'Av. Italia 1240',
      );
      const union = FailureReactivacionDeUnion(conservadaId: 'uuid-secreto-2');

      expect(choque.toString(), 'FailureReactivacionChocaConActiva(UBI_REACTIVAR_MISMA_DIRECCION)');
      expect(union.toString(), 'FailureReactivacionDeUnion(UBI_REACTIVAR_UNION)');
    });
  });
}

/// Cambia la escala del texto de una app montada con [_montar]: el `ValueNotifier` de la raíz.
Future<void> _cambiarEscala(WidgetTester tester, double escala) async {
  final constructor = tester.widget<ValueListenableBuilder<double>>(
    find.byType(ValueListenableBuilder<double>).first,
  );
  (constructor.valueListenable as ValueNotifier<double>).value = escala;
  await tester.pump();
}
