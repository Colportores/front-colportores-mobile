// QA de #345 / PR #355 (vistas 03 «Alta de ubicación» y 07 «Modificar ubicación», HU-UBI-001 y HU-UBI-004):
// lo que cambia el PR (el rótulo «EDITAR UBICACIÓN» con el teclado, la acción fija hasta 2×, el motivo de
// «Registrar» apagado leído una sola vez y la tolerancia de .01 en la medida de la hoja), probado de
// forma independiente de los tests del implementador y en los 8 artboards del canvas:
//   03A·01 GPS preciso · 03A·02 Sin GPS o permiso denegado · 03A·03 GPS impreciso · 03A·04 Número editado
//   07·01 Editar datos · 07·02 Mover el punto · 07·03 Guardado sin conexión · 07·04 Salir con cambios
//
// Con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado). Lo que el implementador
// no mira y acá sí: el motivo se cuenta en TODA la semántica (etiqueta, valor y pista, no solo la etiqueta),
// el barrido de texto va de 1× a 2× de a 0,1× y con barras de arriba no enteras, la hoja no se mueve sola
// después de asentarse, el teclado sube y baja por el foco de verdad (no por un `viewInsets` puesto a mano)
// y el flujo «Cerrar → ¿Descartar los cambios? → Seguir editando» no pierde lo escrito.
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/medida_hoja.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_317_arnes.dart' as a;
import '../helpers/mapa_base_falso.dart' show VistaMapaFalsa;
import '../helpers/modificar_ubicacion_qa_307_arnes.dart' as m;
import '../helpers/qa_hojas_teclado_324_arnes.dart';

const _rotuloEditar = 'EDITAR UBICACIÓN';

Finder get _cerrar => find.byTooltip('Cerrar');

Finder get _rotulo => find.text(_rotuloEditar);

/// Toca un campo (lo lleva a la vista y lo toca): el foco y el teclado salen del campo, no de un número.
Future<void> _tocarCampo(
  WidgetTester tester,
  Finder campo,
  Future<void> Function(WidgetTester) asentar,
) async {
  await tester.ensureVisible(campo);
  await tester.pump();
  await tester.tap(campo);
  await asentar(tester);
}

/// Cuántas veces lee el lector de pantalla [texto]: los nodos de la semántica que lo llevan en su
/// etiqueta, su valor o su pista. Los nodos que se funden en su padre no cuentan aparte (ya van en la
/// etiqueta del padre). Mira TODO el árbol, no solo las etiquetas.
int _lecturas(WidgetTester tester, String texto) {
  final raiz = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  var n = 0;
  void visitar(SemanticsNode nodo) {
    if (!nodo.isMergedIntoParent) {
      final d = nodo.getSemanticsData();
      for (final s in [d.label, d.value, d.hint]) {
        if (s.contains(texto)) n++;
      }
    }
    nodo.visitChildren((SemanticsNode hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(raiz);
  return n;
}

/// Lo que el botón apagado dice de sí: su etiqueta más su pista. La lectura única del motivo es la pista
/// del botón (#322/#342) o, desde la decisión del 16/10 en #355, parte de su etiqueta; los tests aceptan
/// las dos formas.
String _lecturaDelBoton(WidgetTester tester, Finder boton) {
  final d = tester.getSemantics(boton).getSemanticsData();
  return '${d.label}|${d.hint}';
}

/// La invariante del rótulo: se dibuja si y solo si el teclado está cerrado.
void _invarianteDelRotulo(WidgetTester tester, String donde) {
  final tecladoArriba = tester.view.viewInsets.bottom > 0;
  expect(
    _rotulo,
    tecladoArriba ? findsNothing : findsOneWidget,
    reason:
        '$donde: ${tecladoArriba ? 'con' : 'sin'} teclado el rótulo '
        '${tecladoArriba ? 'no se dibuja' : 'está'}',
  );
}

/// Que la hoja no se mueva sola: los mismos rectángulos después de 12 cuadros más.
Future<void> _quieta(WidgetTester tester, List<Finder> piezas, String donde) async {
  final antes = [for (final f in piezas) tester.getRect(f)];
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  for (var i = 0; i < piezas.length; i++) {
    expect(tester.getRect(piezas[i]), antes[i], reason: '$donde: la pieza $i se movió sola');
  }
}

/// Lo que se mide de una hoja con el teclado abierto: el campo que se escribe, la acción, la zona que se
/// desplaza y el borde de la hoja.
class _Hoja {
  const _Hoja({
    required this.hoja,
    required this.accion,
    required this.zona,
    required this.campo,
    required this.nombreAccion,
  });

  final Finder hoja;
  final Finder accion;
  final Finder zona;
  final Finder campo;
  final String nombreAccion;
}

_Hoja get _alta => _Hoja(
  hoja: find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
  accion: a.botonRegistrarFijo,
  zona: a.desplazable,
  campo: a.campoNumero,
  nombreAccion: 'Registrar',
);

_Hoja get _edicion => _Hoja(
  hoja: find.ancestor(of: find.byType(HojaModificarDatos), matching: find.byType(Material)).first,
  accion: m.botonGuardar,
  zona: m.zonaDesplazable,
  campo: m.campoNumero,
  nombreAccion: 'Guardar cambios',
);

/// M2 en una hoja ya montada con el teclado abierto: toca el campo, escribe y comprueba que la acción
/// queda FIJA (fuera de lo que se desplaza) si [debeSerFija], entera sobre el teclado y de 48 dp o más;
/// que el campo se ve entero encima de ella; que la hoja no pasa del 80 % y que, asentada, no se mueve.
Future<void> _accionFijaYCampoALaVista(
  WidgetTester tester,
  _Hoja h, {
  required Size tamano,
  required double teclado,
  required String donde,
  required bool debeSerFija,
  required Future<void> Function(WidgetTester) asentar,
  String texto = '1240',
}) async {
  final libre = tamano.height - teclado;
  await _tocarCampo(tester, h.campo, asentar);
  await tester.enterText(h.campo, texto);
  await asentar(tester);
  expect(tester.takeException(), isNull, reason: '$donde: overflow');

  final enLaZona = find.descendant(of: h.zona, matching: h.accion).evaluate().isNotEmpty;
  if (debeSerFija) {
    expect(enLaZona, isFalse, reason: '$donde: «${h.nombreAccion}» debe quedar FIJA al pie');
  }
  if (enLaZona) {
    await tester.ensureVisible(h.accion);
    await tester.pump();
  }
  final hoja = tester.getRect(h.hoja);
  final boton = tester.getRect(h.accion);
  final campo = tester.getRect(h.campo);
  expect(
    hoja.height,
    lessThanOrEqualTo(libre * .8 + .5),
    reason: '$donde: la hoja pasa del 80 % ($hoja)',
  );
  expect(hoja.bottom, closeTo(libre, .5), reason: '$donde: la hoja apoya sobre el teclado ($hoja)');
  expect(boton.top, greaterThanOrEqualTo(0), reason: '$donde: la acción se corta arriba ($boton)');
  expect(
    boton.bottom,
    lessThanOrEqualTo(libre + .5),
    reason: '$donde: el teclado tapa la acción ($boton)',
  );
  expect(boton.height, greaterThanOrEqualTo(47.5), reason: '$donde: la acción mide $boton');
  expect(
    campo.top,
    greaterThanOrEqualTo(hoja.top - .5),
    reason: '$donde: el campo sale de la hoja ($campo)',
  );
  expect(
    campo.bottom,
    lessThanOrEqualTo(libre + .5),
    reason: '$donde: el teclado tapa el campo ($campo)',
  );
  if (!enLaZona) {
    expect(
      campo.bottom,
      lessThanOrEqualTo(boton.top + .5),
      reason: '$donde: el campo queda detrás de la acción ($campo contra $boton)',
    );
  }
  await _quieta(tester, [h.hoja, h.accion, h.campo], donde);
}

void main() {
  setUpAll(cargarTipografias);

  // ---------------------------------------------------------------------------------------------------
  // M3 · el motivo de «Registrar» apagado se lee UNA sola vez, en los 4 artboards del alta (+ variantes),
  // con el teclado cerrado y abierto, a 1×/2×/3× y en los dos teléfonos.
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · M3 · el motivo de «Registrar» apagado se lee una sola vez', () {
    final casos = <(a.EstadoAlta, String)>[
      (a.EstadoAlta.gpsPreciso, TextosAlta.elegiElTipo),
      (a.EstadoAlta.sinGps, TextosAlta.marcaElPunto),
      (a.EstadoAlta.gpsImpreciso, TextosAlta.elegiPrecision),
      (a.EstadoAlta.numeroEditado, TextosAlta.elegiElTipo),
      (a.EstadoAlta.sinGpsSinConexion, TextosAlta.marcaElPunto),
      (a.EstadoAlta.sinCiudades, TextosAlta.marcaElPunto),
    ];
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        for (final (estado, motivo) in casos) {
          for (final conTeclado in [false, true]) {
            testWidgets(
              '${estado.rotulo} · ${t.nombre} · ${veces(escala)} · teclado ${conTeclado ? 'abierto' : 'cerrado'}',
              (tester) async {
                final handle = tester.ensureSemantics();
                await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala);
                if (conTeclado) {
                  await a.abrirTeclado(tester, t.teclado);
                  await _tocarCampo(tester, a.campoNumero, a.asentar);
                }
                expect(find.text(motivo), findsOneWidget, reason: 'el motivo se sigue viendo');
                expect(_lecturas(tester, motivo), 1, reason: 'el lector lo lee una sola vez');
                expect(
                  _lecturaDelBoton(tester, a.botonRegistrarFijo),
                  contains(motivo),
                  reason: 'y es parte de lo que dice el botón apagado',
                );
                expect(
                  tester.getSemantics(a.botonRegistrarFijo).getSemanticsData().label,
                  startsWith(TextosAlta.registrar),
                  reason: 'el nombre empieza por el texto visible del botón (WCAG 2.5.3)',
                );
                expect(a.registrarHabilitado(tester), isFalse);
                expect(tester.takeException(), isNull);
                handle.dispose();
              },
            );
          }
        }
      }
    }

    testWidgets(
      '03A·01 con «Casa» elegida (el canvas) «Registrar» queda habilitado: sin motivo, sin pista y sin lecturas',
      (tester) async {
        final handle = tester.ensureSemantics();
        await a.abrirEn(tester, a.EstadoAlta.gpsPreciso);
        await tester.tap(find.text('Casa'));
        await a.asentar(tester);
        expect(a.registrarHabilitado(tester), isTrue);
        for (final motivo in [
          TextosAlta.elegiElTipo,
          TextosAlta.marcaElPunto,
          TextosAlta.elegiPrecision,
          TextosAlta.elegiLaCiudad,
        ]) {
          expect(_lecturas(tester, motivo), 0, reason: 'no hay motivo que leer: $motivo');
          expect(find.text(motivo), findsNothing);
        }
        final datos = tester.getSemantics(a.botonRegistrarFijo).getSemanticsData();
        expect(datos.hint, isEmpty);
        expect(datos.label, TextosAlta.registrar, reason: 'habilitado, el nombre es el del botón');
        handle.dispose();
      },
    );

    testWidgets(
      'el motivo cambia al resolver lo que falta y sigue habiendo una sola lectura en cada paso',
      (tester) async {
        final handle = tester.ensureSemantics();
        await a.abrirEn(tester, a.EstadoAlta.gpsImpreciso, teclado: a.tecladoAbierto);
        expect(_lecturas(tester, TextosAlta.elegiPrecision), 1);
        await tester.ensureVisible(find.text(TextosAlta.continuar));
        await tester.pump();
        await tester.tap(find.text(TextosAlta.continuar));
        await a.asentar(tester);
        expect(_lecturas(tester, TextosAlta.elegiPrecision), 0, reason: 'el motivo viejo se fue');
        expect(_lecturas(tester, TextosAlta.elegiElTipo), 1, reason: 'ahora falta el tipo');
        await tester.ensureVisible(find.text('Casa'));
        await tester.pump();
        await tester.tap(find.text('Casa'));
        await a.asentar(tester);
        expect(a.registrarHabilitado(tester), isTrue);
        expect(_lecturas(tester, TextosAlta.elegiElTipo), 0, reason: 'sin motivo, sin lectura');
        final listo = tester.getSemantics(a.botonRegistrarFijo).getSemanticsData();
        expect(listo.hint, isEmpty);
        expect(listo.label, TextosAlta.registrar);
        handle.dispose();
      },
    );

    testWidgets(
      'mientras guarda ("Registrando…") no hay motivo, ni pista ni texto; si falla, el botón vuelve '
      'y lo tipeado sigue',
      (tester) async {
        final handle = tester.ensureSemantics();
        final montada = await a.abrirEn(tester, a.EstadoAlta.gpsPreciso);
        await tester.tap(find.text('Casa'));
        await a.asentar(tester);
        await _tocarCampo(tester, a.campoNumero, a.asentar);
        await tester.enterText(a.campoNumero, '1240');
        await a.asentar(tester);
        montada.repo.bloqueo = Completer<void>();
        await tester.tap(a.botonRegistrarFijo);
        await a.asentar(tester);

        expect(find.text(TextosAlta.registrando), findsOneWidget, reason: 'cargando, con contexto');
        for (final motivo in [
          TextosAlta.elegiElTipo,
          TextosAlta.marcaElPunto,
          TextosAlta.elegiPrecision,
        ]) {
          expect(find.text(motivo), findsNothing);
          expect(_lecturas(tester, motivo), 0);
        }
        final datos = tester.getSemantics(a.botonRegistrarFijo).getSemanticsData();
        expect(datos.hint, isEmpty, reason: 'sin motivo no hay pista');
        expect(
          datos.label,
          TextosAlta.registrando,
          reason: 'cargando, con su contexto y sin motivo',
        );
        // Un segundo toque mientras guarda no anuncia ni registra otra vez.
        final anuncios = escucharAnuncios(tester);
        await tester.tap(a.botonRegistrarFijo, warnIfMissed: false);
        await a.asentar(tester);
        expect(anuncios, isEmpty);
        expect(montada.repo.llamadas, hasLength(1), reason: 'una sola vez');
        montada.repo.bloqueo!.complete();
        await a.asentar(tester);
        handle.dispose();
      },
    );
  });

  // El contraste del motivo ya no lo mira `textContrastGuideline` (el texto salió de la semántica): se
  // calcula acá con los colores del código.
  test('QA #345 · M3 · el motivo (12,5 px) sigue a 4,5:1 sobre la hoja blanca', () {
    double contraste(Color x, Color y) {
      final l1 = x.computeLuminance();
      final l2 = y.computeLuminance();
      return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
    }

    expect(contraste(ColoresAlta.gris, Colors.white), greaterThanOrEqualTo(4.5));
  });

  // ---------------------------------------------------------------------------------------------------
  // M2 · la acción queda FIJA con el teclado abierto hasta 2×, en 360×640 y 412×915: barrido de 1,0× a
  // 2,0× de a 0,1× (el implementador mira 1×, 1,3×, 2× y 3×), con el teclado levantado por el foco.
  // ---------------------------------------------------------------------------------------------------
  final escalas = [for (var i = 10; i <= 20; i++) i / 10];

  group('QA #345 · M2 · 03 · «Registrar» fijo de 1,0× a 2,0×', () {
    for (final t in telefonos) {
      for (final estado in [
        a.EstadoAlta.gpsPreciso,
        a.EstadoAlta.sinGps,
        a.EstadoAlta.gpsImpreciso,
        a.EstadoAlta.numeroEditado,
      ]) {
        testWidgets('${estado.rotulo} · ${t.nombre} · texto de 1,0× a 2,0×', (tester) async {
          for (final escala in escalas) {
            tester.view.resetViewInsets();
            await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala, teclado: t.teclado);
            await _accionFijaYCampoALaVista(
              tester,
              _alta,
              tamano: t.tamano,
              teclado: t.teclado,
              donde: '${estado.rotulo} ${t.nombre} ${veces(escala)}',
              debeSerFija: true,
              asentar: a.asentar,
            );
            // Desmonta antes de montar la siguiente escala.
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });

  group('QA #345 · M2 · 07 · «Guardar cambios» fijo de 1,0× a 2,0×', () {
    for (final t in telefonos) {
      testWidgets('07·01 · ${t.nombre} · texto de 1,0× a 2,0×', (tester) async {
        for (final escala in escalas) {
          tester.view.resetViewInsets();
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await m.abrirTeclado(tester, alto: t.teclado);
          await _accionFijaYCampoALaVista(
            tester,
            _edicion,
            tamano: t.tamano,
            teclado: t.teclado,
            donde: '07·01 ${t.nombre} ${veces(escala)}',
            debeSerFija: true,
            asentar: m.asentar,
          );
          expect(_rotulo, findsNothing, reason: '07·01 ${t.nombre} ${veces(escala)}: sin rótulo');
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  group(
    'QA #345 · M2 · barras de arriba no enteras (notch, recorte) y barra de abajo fraccionaria',
    () {
      for (final t in telefonos) {
        for (final barra in [27.43, 33.7, 41.2]) {
          for (final escala in [1.15, 1.3, 1.75, 2.0]) {
            testWidgets('03A·01 · ${t.nombre} · barra ${barra}dp · ${veces(escala)}', (
              tester,
            ) async {
              await a.abrirEn(
                tester,
                a.EstadoAlta.gpsPreciso,
                tamano: t.tamano,
                escala: escala,
                barraSuperior: barra,
                barraInferior: 16.3,
              );
              tester.view.viewInsets = FakeViewPadding(bottom: t.teclado);
              tester.view.padding = FakeViewPadding(top: barra);
              await a.asentar(tester);
              await _tocarCampo(tester, a.campoNumero, a.asentar);
              expect(tester.takeException(), isNull);
              await _quieta(tester, [_alta.hoja, _alta.accion, _alta.campo], 'barra $barra');
              final boton = tester.getRect(a.botonRegistrarFijo);
              expect(boton.bottom, lessThanOrEqualTo(t.tamano.height - t.teclado + .5));
              expect(boton.top, greaterThanOrEqualTo(0));
            });
            testWidgets('07·01 · ${t.nombre} · barra ${barra}dp · ${veces(escala)}', (
              tester,
            ) async {
              await abrirEdicionQa(
                tester,
                tamano: t.tamano,
                escala: escala,
                barraSuperior: barra,
                barraInferior: 16.3,
              );
              await m.abrirTeclado(tester, alto: t.teclado);
              await _tocarCampo(tester, m.campoNumero, m.asentar);
              expect(tester.takeException(), isNull);
              expect(_rotulo, findsNothing);
              await _quieta(tester, [
                _edicion.hoja,
                _edicion.accion,
                _edicion.campo,
              ], 'barra $barra');
              await m.cerrarTeclado(tester);
              expect(_rotulo, findsOneWidget);
              expect(tester.takeException(), isNull);
            });
          }
        }
      }
    },
  );

  // ---------------------------------------------------------------------------------------------------
  // 07·01 · el rótulo con el teclado que sube y baja por el foco de verdad.
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · 07·01 · el rótulo sigue al teclado real', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets(
          '${t.nombre} · ${veces(escala)}: tocar el campo oculta el rótulo, "listo" del teclado lo devuelve '
          'y vuelve a su lugar exacto',
          (tester) async {
            final handle = tester.ensureSemantics();
            await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
            final origen = tester.getRect(_rotulo);
            final bajoElRotulo = tester.getRect(find.byType(VistaMapaFalsa).first);
            _invarianteDelRotulo(tester, 'cerrado');

            for (var vez = 0; vez < 3; vez++) {
              await tester.ensureVisible(m.campoNumero);
              await tester.pump();
              await tester.tap(m.campoNumero);
              await m.asentarConTeclado(tester);
              expect(tester.testTextInput.isVisible, isTrue);
              _invarianteDelRotulo(tester, 'vuelta $vez, abierto');
              expect(
                find.bySemanticsLabel(_rotuloEditar),
                findsNothing,
                reason: 'tampoco en la semántica',
              );

              await tester.testTextInput.receiveAction(TextInputAction.done);
              await m.asentarConTeclado(tester);
              expect(tester.testTextInput.isVisible, isFalse);
              _invarianteDelRotulo(tester, 'vuelta $vez, cerrado');
              expect(tester.getRect(_rotulo), origen, reason: 'vuelve exactamente a su lugar');
              expect(
                find.bySemanticsLabel(_rotuloEditar),
                findsOneWidget,
                reason: 'y vuelve a la semántica',
              );
              expect(tester.getRect(find.byType(VistaMapaFalsa).first), bajoElRotulo);
            }
            expect(tester.takeException(), isNull);
            handle.dispose();
          },
        );
      }
    }
  });

  // ---------------------------------------------------------------------------------------------------
  // 07·04 · «Cerrar» con el teclado arriba y lo escrito: el diálogo, «Seguir editando» y «Descartar».
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · 07·04 · salir con cambios sin guardar con el teclado arriba', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets(
          '${t.nombre} · ${veces(escala)}: «Seguir editando» conserva lo escrito y el rótulo sigue al '
          'teclado; «Descartar» sale sin guardar',
          (tester) async {
            final repo = await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
            await tester.ensureVisible(m.campoNumero);
            await tester.pump();
            await tester.tap(m.campoNumero);
            await tester.enterText(m.campoNumero, '1238');
            await m.asentarConTeclado(tester);
            _invarianteDelRotulo(tester, 'escribiendo');

            await tester.ensureVisible(_cerrar);
            await tester.pump();
            await tester.tap(_cerrar, warnIfMissed: false);
            await m.asentarConTeclado(tester, 14);
            expect(find.text('¿Descartar los cambios?'), findsOneWidget, reason: '07·04');
            expect(find.textContaining('Si salís ahora, se pierden.'), findsOneWidget);
            // El overflow que el diálogo tiene mientras el teclado termina de bajar (360×640 a 3×) se mide
            // aparte, en el grupo de abajo; acá importa el flujo.
            tester.takeException();

            // Los dos botones se alcanzan aunque el teclado siga arriba.
            for (final boton in ['Seguir editando', 'Descartar']) {
              await tester.ensureVisible(find.text(boton));
              await tester.pump();
              final r = tester.getRect(find.text(boton));
              expect(
                r.bottom,
                lessThanOrEqualTo(t.tamano.height + .5),
                reason: '«$boton» queda fuera: $r',
              );
            }

            tester.takeException();
            await tester.tap(find.text('Seguir editando'));
            await m.asentarConTeclado(tester, 14);
            expect(find.text('¿Descartar los cambios?'), findsNothing);
            expect(
              find.widgetWithText(TextField, '1238'),
              findsOneWidget,
              reason: 'lo escrito sigue',
            );
            expect(m.botonGuardar, findsOneWidget);
            _invarianteDelRotulo(tester, 'después de «Seguir editando»');
            expect(repo.escrituras, isEmpty);

            // Ahora sí: sale descartando.
            await tester.ensureVisible(_cerrar);
            await tester.pump();
            await tester.tap(_cerrar, warnIfMissed: false);
            await m.asentarConTeclado(tester, 14);
            await tester.ensureVisible(find.text('Descartar'));
            await tester.pump();
            await tester.tap(find.text('Descartar'));
            await m.asentarConTeclado(tester, 14);
            expect(find.text('abrir'), findsOneWidget, reason: 'volvió a la pantalla de abajo');
            expect(repo.escrituras, isEmpty, reason: 'descartar no guarda');
            tester.takeException();
          },
        );
      }
    }
  });

  group('QA #345 · 07·04 · el diálogo no desborda mientras el teclado termina de bajar', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        // 360×640 a 3× desbordaba 22 dp en los cuadros en que el teclado (300 dp) todavía bajaba (QA de
        // #355, arreglado en #358: las acciones van en la zona que se desplaza).
        testWidgets('${t.nombre} · ${veces(escala)}', (tester) async {
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await tester.ensureVisible(m.campoNumero);
          await tester.pump();
          await tester.tap(m.campoNumero);
          await tester.enterText(m.campoNumero, '1238');
          await m.asentarConTeclado(tester);
          expect(tester.view.viewInsets.bottom, greaterThan(0), reason: 'el teclado está arriba');
          tester.takeException();

          await tester.tap(_cerrar, warnIfMissed: false);
          // Lo que el framework hace al abrir el diálogo: pide ocultar el teclado en el primer cuadro y
          // el sistema lo baja de a poco; el diálogo se arma con cada alto intermedio.
          for (var cuadro = 0; cuadro < 20; cuadro++) {
            await tester.pump(const Duration(milliseconds: 16));
            final bajando = tester.view.viewInsets.bottom;
            if (bajando > 0) m.ponerTeclado(tester, math.max(0, bajando - 20));
            expect(
              tester.takeException(),
              isNull,
              reason: 'cuadro $cuadro, teclado ${bajando.round()} dp',
            );
          }
          expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        });
      }
    }
  });

  // ---------------------------------------------------------------------------------------------------
  // 07·02 y 07·03 · los otros dos artboards de la vista 07 no se rompen con el rótulo condicionado.
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · 07·02 y 07·03 · los otros artboards', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets(
          '07·02 Mover el punto · ${t.nombre} · ${veces(escala)}: entra desde el teclado cerrado y '
          '«MOVER EL PUNTO» está, con las dos acciones enteras',
          (tester) async {
            await abrirEdicionQa(tester, tamano: t.tamano, escala: escala, barraInferior: 24);
            await tester.tap(m.campoNumero);
            await m.asentarConTeclado(tester);
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await m.asentarConTeclado(tester);
            await tester.tap(find.text('Mover el punto'));
            await m.asentarConTeclado(tester);
            expect(find.text('MOVER EL PUNTO'), findsOneWidget);
            expect(_rotulo, findsNothing);
            for (final accion in ['Guardar posición', 'Cancelar']) {
              final r = tester.getRect(find.text(accion));
              expect(r.top, greaterThanOrEqualTo(0), reason: '«$accion» $r');
              expect(
                r.bottom,
                lessThanOrEqualTo(t.tamano.height - 24 + .5),
                reason: '«$accion» $r',
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      '07·03 Guardado sin conexión: guarda con el teclado arriba y el aviso del canvas queda',
      (tester) async {
        final repo = await abrirEdicionQa(tester, conexion: TipoConexion.sinConexion);
        await tester.tap(m.campoNumero);
        await tester.enterText(m.campoNumero, '1240');
        await m.asentarConTeclado(tester);
        expect(_rotulo, findsNothing);
        await tester.tap(m.botonGuardar);
        await m.asentarConTeclado(tester);
        expect(repo.escrituras, hasLength(1));
        expect(find.text('abrir'), findsOneWidget);
        expect(
          find.text(
            'Cambios guardados en tu celular. El estado se sincroniza cuando vuelva la conexión.',
          ),
          findsOneWidget,
          reason: 'texto literal del canvas 07·03',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------------------------------
  // Textos literales del canvas en los 4 artboards del alta (la parte que la HU y el canvas fijan).
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · textos del canvas en 03A', () {
    testWidgets('03A·02 Sin GPS: aviso, acción y motivo del canvas', (tester) async {
      await a.abrirEn(tester, a.EstadoAlta.sinGps);
      expect(
        find.text('No tenemos tu ubicación. Tocá el mapa donde está el lugar o activá el GPS.'),
        findsOneWidget,
      );
      expect(find.text('Activar GPS'), findsOneWidget);
      expect(find.text('Tocá donde está el lugar'), findsOneWidget);
      expect(find.text('Marcá el punto en el mapa para registrar.'), findsOneWidget);
    });

    testWidgets('03A·03 GPS impreciso: el aviso literal de la HU y sus dos acciones', (
      tester,
    ) async {
      await a.abrirEn(tester, a.EstadoAlta.gpsImpreciso);
      expect(
        find.text('Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?'),
        findsOneWidget,
      );
      expect(find.text('Ajustar manualmente'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });

    testWidgets('03A·04 Número editado: «Editado» y «Usar …» con el número del mapa', (
      tester,
    ) async {
      // El arnés pone el geocodificador en 1234: el número escrito (1238) queda «Editado» y se ofrece
      // «Usar 1234» (en el canvas, 1236 contra 1250).
      await a.abrirEn(tester, a.EstadoAlta.numeroEditado);
      expect(find.text('Editado'), findsWidgets);
      expect(find.textContaining('Usar 1234'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------
  // M4 · la tolerancia de .01 de la medida de la hoja: propiedades sobre muchas entradas.
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · M4 · propiedades de la medida de la hoja', () {
    int rango(LugarDeLaAccion l) => switch (l) {
      LugarDeLaAccion.fijaConMotivoAbajo => 0,
      LugarDeLaAccion.fijaConMotivoArriba => 1,
      LugarDeLaAccion.alFinalDeLoQueSeDesplaza => 2,
    };

    test('lugarDeLaAccion es monótona: más lugar nunca manda la acción a un lugar peor', () {
      final azar = math.Random(345);
      for (var i = 0; i < 20000; i++) {
        final boton = 48 + azar.nextDouble() * 40;
        final motivo = azar.nextBool() ? 0.0 : 10 + azar.nextDouble() * 60;
        final campo = azar.nextInt(5) == 0 ? null : 40 + azar.nextDouble() * 60;
        final contenido = 80 + azar.nextDouble() * 500;
        final teclado = azar.nextBool();
        final menos = lugarDeLaAccion(
          contenido: contenido,
          tecladoAbierto: teclado,
          boton: boton,
          motivo: motivo,
          campo: campo,
        );
        final mas = lugarDeLaAccion(
          contenido: contenido + azar.nextDouble() * 80,
          tecladoAbierto: teclado,
          boton: boton,
          motivo: motivo,
          campo: campo,
        );
        expect(
          rango(mas),
          lessThanOrEqualTo(rango(menos)),
          reason: 'contenido $contenido boton $boton motivo $motivo campo $campo teclado $teclado',
        );
      }
    });

    test('dos caminos al mismo número (otra asociación de la suma) dan el mismo lugar', () {
      final azar = math.Random(3450);
      for (var i = 0; i < 20000; i++) {
        final boton = 48 + (azar.nextInt(4000) / 100);
        final motivo = 10 + (azar.nextInt(6000) / 100);
        final campo = 40 + (azar.nextInt(6000) / 100);
        // Lo que `lugarDeLaAccion` suma, en el orden de la función...
        final fijo = separacionDelBoton + boton + (separacionDelMotivo + motivo);
        final pide = fijo + (campo + rellenoDelCampo);
        // ...y lo que la hoja de afuera le da, restado y vuelto a sumar en otro orden.
        final tope = pide + cromoDeLaHoja;
        final contenido = (tope - 10 - 4) - (cromoDeLaHoja - 14);
        final l = lugarDeLaAccion(
          contenido: contenido,
          tecladoAbierto: true,
          boton: boton,
          motivo: motivo,
          campo: campo,
        );
        expect(l, LugarDeLaAccion.fijaConMotivoAbajo, reason: 'pide $pide, da $contenido');
      }
    });

    test('topeDeLaHoja: nunca baja del 62 % ni pasa del 80 % del cuerpo, con o sin teclado', () {
      final azar = math.Random(34500);
      for (var i = 0; i < 20000; i++) {
        final cuerpo = 200 + azar.nextDouble() * 700;
        final tope = topeDeLaHoja(
          cuerpo: cuerpo,
          barraDeArriba: azar.nextDouble() * 50,
          barraDeAbajo: azar.nextDouble() * 50,
          tecladoAbierto: azar.nextBool(),
          necesidad: azar.nextInt(4) == 0
              ? null
              : NecesidadHoja(
                  campo: 20 + azar.nextDouble() * 120,
                  boton: 48 + azar.nextDouble() * 50,
                  motivo: azar.nextBool() ? 0 : 8 + azar.nextDouble() * 80,
                ),
        );
        expect(
          tope,
          greaterThanOrEqualTo(cuerpo * fraccionDeLaHoja - 1e-9),
          reason: 'cuerpo $cuerpo',
        );
        expect(
          tope,
          lessThanOrEqualTo(cuerpo * math.max(fraccionConTeclado, fraccionDeLaHoja) + 1e-9),
        );
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------
  // Capturas (solo con --dart-define=QA_CAPTURAS=true): cada artboard con el teclado cerrado y abierto.
  // ---------------------------------------------------------------------------------------------------
  group('QA #345 · capturas', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        for (final estado in [
          a.EstadoAlta.gpsPreciso,
          a.EstadoAlta.sinGps,
          a.EstadoAlta.gpsImpreciso,
          a.EstadoAlta.numeroEditado,
        ]) {
          testWidgets('03 ${estado.name} ${t.nombre} ${veces(escala)}', (tester) async {
            await a.cargarIconosParaCapturas(tester);
            await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala);
            await capturarEn(
              tester,
              a.raizCaptura,
              '355_03_${estado.name}_${t.nombre}_${veces(escala)}_cerrado',
            );
            await a.abrirTeclado(tester, t.teclado);
            await _tocarCampo(tester, a.campoNumero, a.asentar);
            await capturarEn(
              tester,
              a.raizCaptura,
              '355_03_${estado.name}_${t.nombre}_${veces(escala)}_abierto',
            );
          }, skip: !conCapturas);
        }
        testWidgets('07 editar ${t.nombre} ${veces(escala)}', (tester) async {
          await a.cargarIconosParaCapturas(tester);
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await capturarEn(tester, raizQa, '355_07_editar_${t.nombre}_${veces(escala)}_cerrado');
          await m.abrirTeclado(tester, alto: t.teclado);
          await _tocarCampo(tester, m.campoNumero, m.asentar);
          await capturarEn(tester, raizQa, '355_07_editar_${t.nombre}_${veces(escala)}_abierto');
        }, skip: !conCapturas);
        testWidgets('07 mover ${t.nombre} ${veces(escala)}', (tester) async {
          await a.cargarIconosParaCapturas(tester);
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await tester.tap(find.text('Mover el punto'));
          await m.asentar(tester);
          await capturarEn(tester, raizQa, '355_07_mover_${t.nombre}_${veces(escala)}');
        }, skip: !conCapturas);
        testWidgets('07 descartar ${t.nombre} ${veces(escala)}', (tester) async {
          await a.cargarIconosParaCapturas(tester);
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await tester.enterText(m.campoNumero, '1238');
          await m.asentar(tester);
          await tester.tap(_cerrar);
          await m.asentar(tester);
          await capturarEn(tester, raizQa, '355_07_descartar_${t.nombre}_${veces(escala)}');
        }, skip: !conCapturas);
      }
    }
  });
}
