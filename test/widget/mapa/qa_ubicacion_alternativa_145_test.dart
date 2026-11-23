// QA de #145 (HU-UBI-013, vista 22 grupo A): lo que el implementador no cubrió de los casos límite.
//
// - Doble toque sobre «Quitar» de la tarjeta: una sola hoja.
// - «Quitando…»: ni el «atrás» de sistema ni un toque afuera cierran la hoja y se pierde el resultado.
// - Volver atrás de la ficha mientras se guarda la alternativa: sin excepción ni estado colgado.
// - Falla al guardar que se lanza (no un `Failure`): el aviso sale y nada queda trabado.
// - Búsqueda del selector: solo espacios, emoji, texto pegado larguísimo, mayúsculas, acentos, signos.
// - Los avisos de error se anuncian (región viva) y la tarjeta vigente dice qué es para el lector.
// - Reentrada a la ficha después de una falla: el aviso viejo no queda.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ficha_persona_arnes.dart';

/// `--dart-define=QA_HALLAZGOS=true` corre los tests de hallazgos (los que llevan `skip`).
const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  final italia = ubicacionParaAlternativa('ub-2');
  final mataojo = ubicacionParaAlternativa(
    'ub-3',
    calle: 'Mataojo',
    numero: '2051',
    tipo: TipoUbicacion.casa,
  );
  final rambla = ubicacionParaAlternativa(
    'ub-4',
    calle: 'Rambla República de México',
    numero: '6001',
    tipo: TipoUbicacion.edificio,
  );

  const alto = Size(390, 1700);

  MundoFicha mundo({
    EstadoUbicacionAlternativa estado = const SinUbicacionAlternativa(),
    List<Ubicacion>? candidatas,
  }) {
    final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    m.alternativas
      ..ponerEstado(estado)
      ..ponerCandidatas(candidatas ?? [italia, mataojo, rambla]);
    return m;
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await asentar(tester);
  }

  final sin = find.byKey(ClavesAlternativa.sinAlternativa);
  final quitar = find.byKey(ClavesAlternativa.quitar);
  final buscar = find.byKey(ClavesAlternativa.selectorBuscar);
  final hoja = find.byKey(ClavesAlternativa.hojaQuitar);
  final confirmar = find.byKey(ClavesAlternativa.hojaQuitarConfirmar);

  group('«Quitar» de la tarjeta', () {
    testWidgets('dos toques seguidos abren una sola hoja', (tester) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia));
      await montarFicha(tester, m, tamano: alto);

      await tester.ensureVisible(quitar);
      await tester.pump();
      // Sin dejar correr un cuadro entre toque y toque: la hoja todavía no se abrió.
      await tester.tap(quitar);
      await tester.tap(quitar);
      await asentar(tester);

      expect(hoja, findsOneWidget);
      // Cerrar esa única hoja deja la ficha: no hay una segunda debajo.
      await tester.tap(find.byKey(ClavesAlternativa.hojaQuitarCancelar));
      await asentar(tester);
      expect(hoja, findsNothing);
      expect(find.byKey(ClavesAlternativa.vigente), findsOneWidget);
    });
  });

  group('«Quitando…» no se puede cerrar', () {
    testWidgets('el «atrás» de sistema y un toque afuera no cierran, y al terminar se cierra', (
      tester,
    ) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia))
        ..alternativas.compuertaQuitar = Completer<void>();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(confirmar);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Quitando…'), findsOneWidget);

      // El «atrás» de sistema.
      await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
      await tester.pump(const Duration(milliseconds: 300));
      expect(hoja, findsOneWidget);

      // Un toque en la zona oscura de afuera.
      await tester.tapAt(const Offset(195, 40));
      await tester.pump(const Duration(milliseconds: 300));
      expect(hoja, findsOneWidget);

      // Termina de escribir: la hoja se va, la ficha avisa y vuelve a ofrecer «Elegir».
      m.alternativas.compuertaQuitar!.complete();
      await asentar(tester);
      expect(hoja, findsNothing);
      expect(m.alternativas.quitadas, ['per-1']);
      expect(sin, findsOneWidget);
      expect(find.text('Las cobranzas de María se van a proponer en su casa.'), findsOneWidget);
    });

    testWidgets('«Cancelar» está apagado mientras escribe', (tester) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia))
        ..alternativas.compuertaQuitar = Completer<void>();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);

      await tester.tap(confirmar);
      await tester.pump(const Duration(milliseconds: 100));

      final cancelar = find.byKey(ClavesAlternativa.hojaQuitarCancelar);
      expect(tester.widget<TextButton>(cancelar).onPressed, isNull);
      expect(tester.widget<FilledButton>(confirmar).onPressed, isNull);

      m.alternativas.compuertaQuitar!.complete();
      await asentar(tester);
    });
  });

  group('acciones que se cruzan', () {
    testWidgets('volver atrás de la ficha mientras guarda no deja excepciones ni nada colgado', (
      tester,
    ) async {
      final m = mundo()..alternativas.compuertaEstablecer = Completer<void>();
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.guardando), findsOneWidget);

      await volverAtras(tester);
      expect(find.byKey(ClavesAlternativa.seccion), findsNothing);

      // La escritura termina con la ficha ya cerrada.
      m.alternativas.compuertaEstablecer!.complete();
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(m.alternativas.establecidas, ['ub-2']);

      // Reentrar: lo guardado está y no queda «Guardando…» ni aviso viejo.
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.vigente), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.guardando), findsNothing);
      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsNothing);
    });

    testWidgets('una falla que se lanza al guardar da el aviso del canvas y nada queda trabado', (
      tester,
    ) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(StateError('disco lleno'));
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.guardando), findsNothing);
      expect(find.byKey(ClavesAlternativa.reintentarGuardar), findsOneWidget);
      // Lo que se tocó sigue: «Reintentar» lo guarda.
      await tocar(tester, find.byKey(ClavesAlternativa.reintentarGuardar));
      expect(m.alternativas.establecidas, ['ub-2', 'ub-2']);
      expect(find.byKey(ClavesAlternativa.vigente), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsNothing);
    });

    testWidgets('después de una falla, volver atrás y reentrar no trae el aviso viejo', (
      tester,
    ) async {
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsOneWidget);

      await volverAtras(tester);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.errorAlGuardar), findsNothing);
      expect(sin, findsOneWidget);
    });

    testWidgets('quitar con la alternativa ya quitada desde otro lado no rompe la ficha', (
      tester,
    ) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia));
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, quitar);
      // Mientras la hoja está abierta, la alternativa se quita por otro camino (el sync).
      m.alternativas.ponerEstado(const SinUbicacionAlternativa());
      await asentar(tester);

      await tester.tap(confirmar);
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(hoja, findsNothing);
      expect(sin, findsOneWidget);
    });
  });

  group('búsqueda del selector: lo que se escribe', () {
    Future<void> abrir(WidgetTester tester, MundoFicha m) async {
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
    }

    testWidgets('solo espacios muestra la lista entera', (tester) async {
      await abrir(tester, mundo());
      await tester.enterText(buscar, '     ');
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.selectorSinResultados), findsNothing);
    });

    testWidgets('sin mayúsculas, sin acentos y sin el punto igual encuentra «Av. Italia»', (
      tester,
    ) async {
      await abrir(tester, mundo());
      for (final texto in ['AV ITALIA', 'av. italia 28', 'ítalia', 'italia  2810', 'negocio']) {
        await tester.enterText(buscar, texto);
        await asentar(tester);
        expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget, reason: texto);
        expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsNothing, reason: texto);
      }
    });

    testWidgets('encuentra «República de México» sin los acentos', (tester) async {
      await abrir(tester, mundo());
      await tester.enterText(buscar, 'republica mexico');
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.fila('ub-4')), findsOneWidget);
    });

    testWidgets('emoji y signos de regex no rompen: dicen «Ninguna ubicación coincide»', (
      tester,
    ) async {
      await abrir(tester, mundo());
      for (final texto in ['🏪', '.*', '(', r'\', '[a-z', '%', "'; DROP TABLE ubicacion;--"]) {
        await tester.enterText(buscar, texto);
        await asentar(tester);
        expect(tester.takeException(), isNull, reason: texto);
        expect(find.byKey(ClavesAlternativa.selectorSinResultados), findsOneWidget, reason: texto);
        // Con nada para elegir, «+ Registrar una ubicación» sigue a mano.
        expect(find.byKey(ClavesAlternativa.selectorRegistrarMas), findsOneWidget, reason: texto);
      }
    });

    testWidgets('un texto pegado de 5.000 caracteres no rompe y la ✕ del campo lo borra', (
      tester,
    ) async {
      await abrir(tester, mundo());
      await tester.enterText(buscar, 'Zzz ' * 1250);
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAlternativa.selectorSinResultados), findsOneWidget);
      await tester.tap(find.byKey(ClavesAlternativa.selectorBorrarBusqueda));
      await asentar(tester);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsOneWidget);
    });

    testWidgets('el texto buscado sigue después de un error al leer y «Reintentar»', (
      tester,
    ) async {
      final m = mundo();
      await abrir(tester, m);
      await tester.enterText(buscar, 'Mataojo');
      await asentar(tester);

      // La lectura se cae: sin lista no hay campo, pero el texto no se pierde al volver.
      m.alternativas.ponerCandidatas(const []);
      await asentar(tester);
      m.alternativas.ponerCandidatas([italia, mataojo, rambla]);
      await asentar(tester);

      expect(find.byKey(ClavesAlternativa.fila('ub-3')), findsOneWidget);
      expect(find.byKey(ClavesAlternativa.fila('ub-2')), findsNothing);
    });
  });

  group('lector de pantalla', () {
    testWidgets('el aviso de «No pudimos guardar…» es una región viva con «Reintentar» aparte', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);
      await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
      await asentar(tester);

      final aviso = tester.getSemantics(find.byKey(ClavesAlternativa.errorAlGuardar));
      final datos = aviso.getSemanticsData();
      final vivos = <String>[];
      void juntar(SemanticsNode n) {
        final d = n.getSemanticsData();
        if (d.flagsCollection.isLiveRegion) vivos.add(d.label);
        n.visitChildren((h) {
          juntar(h);
          return true;
        });
      }

      juntar(aviso);
      expect(datos.label + vivos.join(), contains('No pudimos guardar la ubicación alternativa'));
      expect(vivos, isNotEmpty, reason: 'el aviso rojo de 22A·09 no se anuncia solo');
      expect(
        tester.getSemantics(find.byKey(ClavesAlternativa.reintentarGuardar)),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Reintentar',
        ),
      );
      semantica.dispose();
    });

    testWidgets('el error al leer del selector se anuncia y su «Reintentar» es un botón', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = mundo()..alternativas.errorAlObservarCandidatas = StateError('sin db');
      await montarFicha(tester, m, tamano: alto);
      await tocar(tester, sin);

      final aviso = tester.getSemantics(find.byKey(ClavesAlternativa.selectorError));
      var vivo = false;
      void buscarVivo(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) vivo = true;
        n.visitChildren((h) {
          buscarVivo(h);
          return true;
        });
      }

      buscarVivo(aviso);
      expect(vivo, isTrue);
      expect(find.byKey(ClavesAlternativa.selectorReintentar), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('la tarjeta vigente dice qué es: SE COBRA ACÁ, la dirección y el tipo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final m = mundo(estado: UbicacionAlternativaVigente(italia));
      await montarFicha(tester, m, tamano: alto);
      await tester.ensureVisible(find.byKey(ClavesAlternativa.vigente));
      await tester.pump();

      final etiqueta = tester.getSemantics(find.byKey(ClavesAlternativa.vigente)).label;
      expect(etiqueta, contains('SE COBRA ACÁ'));
      expect(etiqueta, contains('Av. Italia 2810'));
      expect(etiqueta, contains('Negocio'));
      semantica.dispose();
    });
  });

  group('hallazgos', () {
    Future<void> abrirHojaConFalla(WidgetTester tester, Size tamano, double escala) async {
      final m = mundo(estado: UbicacionAlternativaVigente(italia))
        ..alternativas.resultadosQuitar.add(const FailureInesperado());
      await montarFicha(tester, m, tamano: tamano, escala: escala);
      await tester.scrollUntilVisible(quitar, 300, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(quitar);
      await asentar(tester);
      await tester.tap(confirmar);
      await asentar(tester);
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// El aviso rojo de la hoja entra entero en la parte que se ve (sin desplazar).
    void avisoEntero(WidgetTester tester) {
      final aviso = tester.getRect(find.byKey(ClavesAlternativa.hojaQuitarError));
      final zona = tester.getRect(
        find.descendant(of: hoja, matching: find.byType(SingleChildScrollView)),
      );
      expect(
        aviso.bottom,
        lessThanOrEqualTo(zona.bottom + 0.5),
        reason:
            'el aviso baja hasta ${aviso.bottom.toStringAsFixed(0)} y la zona que se ve termina '
            'en ${zona.bottom.toStringAsFixed(0)}',
      );
    }

    // Controles: con texto 1,0 el aviso se ve entero, en los dos tamaños.
    for (final (tamano, escala) in [(const Size(412, 915), 1.0), (const Size(360, 640), 1.0)]) {
      testWidgets('hoja de quitar con falla: el aviso se ve entero a ${tamano.width.toInt()}×'
          '${tamano.height.toInt()} con texto $escala', (tester) async {
        await abrirHojaConFalla(tester, tamano, escala);
        avisoEntero(tester);
      });
    }

    group(
      'hoja de quitar con falla con texto 2,0',
      skip: _hallazgos
          ? false
          : 'QA #145: la hoja «¿Quitar …?» con texto 2,0 deja el aviso «No pudimos quitar» fuera de '
                'la parte que se ve (a 412×915 baja a 1021 con la zona terminando en 768; a 360×640 '
                'solo asoma la primera línea)',
      () {
        for (final tamano in [const Size(412, 915), const Size(360, 640)]) {
          testWidgets('el aviso rojo se ve entero sin desplazar a ${tamano.width.toInt()}×'
              '${tamano.height.toInt()}', (tester) async {
            await abrirHojaConFalla(tester, tamano, 2.0);
            avisoEntero(tester);
          });
        }
      },
    );

    group(
      'tipografía de los botones de texto',
      skip: _hallazgos
          ? false
          : 'QA #145: «Quitar», «Reintentar», «Elegir otra» y «+ Registrar una ubicación» pisan el '
                'textStyle sin fontFamily y salen con la fuente del sistema, no con Inter',
      () {
        String? familia(WidgetTester tester, Finder texto) =>
            tester.renderObject<RenderParagraph>(texto).text.style?.fontFamily;

        testWidgets('control: la dirección de la tarjeta sí usa Inter', (tester) async {
          await montarFicha(
            tester,
            mundo(estado: UbicacionAlternativaVigente(italia)),
            tamano: alto,
          );
          await tester.scrollUntilVisible(quitar, 300, scrollable: find.byType(Scrollable).first);
          expect(familia(tester, find.text('Av. Italia 2810')), 'Inter');
        });

        testWidgets('«Quitar» de la tarjeta usa Inter como el resto de la ficha', (tester) async {
          await montarFicha(
            tester,
            mundo(estado: UbicacionAlternativaVigente(italia)),
            tamano: alto,
          );
          await tester.scrollUntilVisible(quitar, 300, scrollable: find.byType(Scrollable).first);
          expect(
            familia(tester, find.descendant(of: quitar, matching: find.text('Quitar'))),
            'Inter',
          );
        });

        testWidgets('«Reintentar» del aviso de la ficha usa Inter', (tester) async {
          final m = mundo()..alternativas.resultadosEstablecer.add(const FailureInesperado());
          await montarFicha(tester, m, tamano: alto);
          await tocar(tester, sin);
          await tester.tap(find.byKey(ClavesAlternativa.fila('ub-2')));
          await asentar(tester);
          expect(
            familia(
              tester,
              find.descendant(
                of: find.byKey(ClavesAlternativa.reintentarGuardar),
                matching: find.text('Reintentar'),
              ),
            ),
            'Inter',
          );
        });

        testWidgets('«+ Registrar una ubicación» del selector usa Inter', (tester) async {
          await montarFicha(tester, mundo(), tamano: alto);
          await tocar(tester, sin);
          expect(
            familia(
              tester,
              find.descendant(
                of: find.byKey(ClavesAlternativa.selectorRegistrarMas),
                matching: find.text('+ Registrar una ubicación'),
              ),
            ),
            'Inter',
          );
        });
      },
    );
  });
}
