// QA de #307 / PR #321 (vista 07 «Modificar ubicación», HU-UBI-004): «Abrir de nuevo» queda a la vista
// cuando sale el aviso «cambió mientras la editabas». Complementa a `modificar_ubicacion_geometria_test.dart`
// (grupo `#307`: 360×640, 320×568 y 412×915 al 200 %, teclado en 360×640) con lo que ese grupo no
// recorre: el barrido de texto 1×, 1,3×, 2× y 3× en los dos teléfonos chicos, con y sin la barra de
// 3 botones del sistema, con y sin teclado de 300 dp, y la hoja desplazada antes de guardar.
//
// Geometría con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado). Las
// guías de accesibilidad van en `modificar_ubicacion_qa_307_guias_test.dart`.
//
// Los tests que documentan un hallazgo van con `skip: true` y, arriba, el comentario
// `// skip: QA #321 — <hallazgo>` (en `testWidgets` el `skip` es un bool).
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/modificar_ubicacion_falsos.dart' show ubicacionGuardada;
import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';

String _x(double escala) => escala == escala.roundToDouble()
    ? '${escala.round()}×'
    : '${escala.toString().replaceAll('.', ',')}×';

Finder get _accion => find.text(TextosModificar.abrirDeNuevo);

/// El objetivo táctil de «Abrir de nuevo» (el botón de texto de 48 dp).
Finder get _objetivo => find.ancestor(of: _accion, matching: find.byType(TextButton));

/// Cuánto del alto de [r] se ve dentro de [zona].
double _visible(Rect r, Rect zona) =>
    (r.bottom.clamp(zona.top, zona.bottom) - r.top.clamp(zona.top, zona.bottom)).toDouble();

/// Lo que se ve de la hoja: el borde de abajo de lo que no tapa la barra del sistema. El teclado ya no
/// cuenta: al salir el aviso la hoja lo cierra.
double _bordeLibre(Size tamano, double barra) => tamano.height - barra;

void main() {
  setUpAll(cargarFuentesReales);

  final telefonos = <(String, Size)>[('360×640', telefono360x640), ('320×568', telefono320x568)];
  final sistemas = <(String, double)>[('sin barra de abajo', 0), ('con barra de 3 botones', 48)];

  // Con teclado, el teclado es el de verdad (`fallarPorCambio(conTeclado: true)`): sube al escribir el
  // número, baja mientras guarda y, al salir el aviso, la hoja lo cierra (ronda 1 de #321). Antes el
  // caso 320×568 · 2× · con teclado iba con `skip`: con el teclado de 300 dp fijo la hoja no tiene
  // lugar ni para sus botones fijos.
  group('QA #321 · «Abrir de nuevo» a la vista apenas sale el aviso (texto hasta 200 %)', () {
    for (final (nombreTel, tamano) in telefonos) {
      for (final escala in [1.0, 1.3, 2.0]) {
        for (final (nombreSis, barra) in sistemas) {
          for (final teclado in [false, true]) {
            testWidgets(
              '$nombreTel · texto ${_x(escala)} · $nombreSis · ${teclado ? 'con' : 'sin'} teclado: '
              'la acción se ve, se toca sin desplazar y «Guardar cambios» sigue entero',
              (tester) async {
                final m = await abrirEdicion(
                  tester,
                  tamano: tamano,
                  escala: escala,
                  barraInferior: barra,
                );
                await fallarPorCambio(tester, m, conTeclado: teclado);

                expect(tester.takeException(), isNull, reason: 'sin overflow');
                // El teclado se cerró con el aviso y no vuelve a subir.
                expect(tester.testTextInput.isVisible, isFalse, reason: 'el teclado no vuelve');
                expect(tester.view.viewInsets.bottom, 0);
                final zona = rectZona(tester);
                final fijo = tester.getRect(botonGuardar);
                final texto = tester.getRect(_accion);
                final objetivo = tester.getRect(_objetivo);
                // El botón fijo se ve entero, por encima de la barra del sistema.
                expect(fijo.top, greaterThanOrEqualTo(0));
                expect(fijo.bottom, lessThanOrEqualTo(_bordeLibre(tamano, barra) + .5));
                // La acción cae dentro de lo que se desplaza (4 dp de holgura: el interlineado de
                // arriba del renglón) y sobre el botón fijo.
                expect(texto.top, greaterThanOrEqualTo(zona.top - 4), reason: 'sin cortar arriba');
                expect(
                  texto.bottom,
                  lessThanOrEqualTo(zona.bottom + .5),
                  reason: 'sin cortar abajo',
                );
                expect(
                  texto.bottom,
                  lessThanOrEqualTo(fijo.top + .5),
                  reason: 'sobre el botón fijo',
                );
                // El objetivo táctil asoma al menos los 24 dp de WCAG 2.5.8 (AA).
                expect(_visible(objetivo, zona), greaterThanOrEqualTo(24));
                // Se toca donde está, sin desplazar: la lectura se repite una sola vez.
                expect(_accion.hitTestable(), findsOneWidget);
                final lecturas = m.repo.lecturas;
                await tester.tap(_accion);
                await asentar(tester);
                expect(_accion, findsNothing, reason: 'el toque llegó');
                expect(m.repo.lecturas, lecturas + 1);
                expect(m.repo.escrituras, isEmpty, reason: 'nunca se pisó lo que cambió');
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  });

  group('QA #321 · la hoja desplazada hacia arriba antes de guardar', () {
    for (final (nombreTel, tamano, escala, barra) in <(String, Size, double, double)>[
      ('360×640', telefono360x640, 2.0, 0),
      ('360×640', telefono360x640, 2.0, 48),
      ('320×568', telefono320x568, 2.0, 48),
    ]) {
      testWidgets('$nombreTel · texto ${_x(escala)} · barra ${barra.round()} dp: el aviso baja y '
          'deja la acción a la vista', (tester) async {
        final m = await abrirEdicion(tester, tamano: tamano, escala: escala, barraInferior: barra);
        await tester.enterText(campoNumero, '1238');
        await asentar(tester);
        // El colportor subió la hoja hasta el principio (el botón fijo no se mueve) y guarda.
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: zonaDesplazable, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(0);
        await tester.pump();
        m.repo.actual = ubicacionGuardada(actualizada: DateTime.utc(2026, 10, 1, 9));
        await tester.tap(botonGuardar);
        await asentar(tester);

        final zona = rectZona(tester);
        final texto = tester.getRect(_accion);
        expect(texto.top, greaterThanOrEqualTo(zona.top - 4));
        expect(texto.bottom, lessThanOrEqualTo(zona.bottom + .5));
        expect(texto.bottom, lessThanOrEqualTo(tester.getRect(botonGuardar).top + .5));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('QA #321 · leer el aviso entero: desplazando hacia arriba se llega a su primer renglón', () {
    for (final (nombreTel, tamano, escala) in <(String, Size, double)>[
      ('360×640', telefono360x640, 2.0),
      ('320×568', telefono320x568, 2.0),
    ]) {
      testWidgets('$nombreTel · texto ${_x(escala)}: nada del aviso queda inalcanzable', (
        tester,
      ) async {
        final m = await abrirEdicion(tester, tamano: tamano, escala: escala);
        await fallarPorCambio(tester, m);

        final scroll = tester.state<ScrollableState>(
          find.descendant(of: zonaDesplazable, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        final aviso = find.ancestor(
          of: find.textContaining('cambió mientras la editabas'),
          matching: find.byType(AvisoAlta),
        );
        expect(aviso, findsOneWidget);
        // Con la hoja al final se ve el pie del aviso y, desplazando, también su tope.
        final enFinal = tester.getRect(_accion);
        expect(enFinal.bottom, lessThanOrEqualTo(rectZona(tester).bottom + .5));
        // Y desplazando hacia arriba se llega a su primer renglón, entero dentro de la zona.
        final primero = find.textContaining('Esta ubicación cambió');
        await Scrollable.ensureVisible(
          tester.element(primero),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          duration: Duration.zero,
        );
        await tester.pump();
        // El párrafo al 200 % es más alto que la zona (134 dp en 320×568): se lee desplazando, con su
        // primer renglón arriba de todo.
        final r = tester.getRect(primero);
        final zona = rectZona(tester);
        expect(r.top, greaterThanOrEqualTo(zona.top - .5), reason: 'su primer renglón se lee');
        expect(r.top, lessThan(zona.bottom));
      });
    }
  });

  group('QA #321 · después de «Abrir de nuevo» en el teléfono más chico', () {
    testWidgets('320×568 · texto 2× · barra de 3 botones: si cambia otra vez, el aviso vuelve a '
        'llevarse a la vista y nunca se escribe sobre lo que cambió', (tester) async {
      final m = await abrirEdicion(
        tester,
        tamano: telefono320x568,
        escala: 2,
        barraInferior: barraDeTresBotones,
      );
      await fallarPorCambio(tester, m);
      await tester.tap(_accion);
      await asentar(tester);
      expect(_accion, findsNothing);

      await fallarPorCambio(tester, m, numero: '1310', hora: 10);

      // Se mide el objetivo táctil (el botón de 48 dp), no solo el texto: lo que se toca tiene que
      // estar entero a la vista.
      final zona = rectZona(tester);
      final objetivo = tester.getRect(_objetivo);
      expect(objetivo.top, greaterThanOrEqualTo(zona.top - .5));
      expect(objetivo.bottom, lessThanOrEqualTo(zona.bottom + .5));
      expect(m.repo.escrituras, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #321 · texto al 300 % (por encima del máximo de Android, que es 200 %)', () {
    for (final (nombreTel, tamano, barra, teclado) in <(String, Size, double, bool)>[
      ('360×640', telefono360x640, 0, false),
      ('360×640', telefono360x640, 48, false),
      ('320×568', telefono320x568, 0, false),
      // 320×568 con barra de 3 botones, sin teclado, al 300 %: «Guardar cambios» (3 renglones, 146 dp)
      // deja 45 dp a lo que se desplaza y «Abrir de nuevo» (102 dp) no se toca por el centro. Fuera de
      // la regla de #324 (que es con el teclado) y por encima del máximo de Android: se quitó (#324).
      ('360×640', telefono360x640, 0, true),
      ('320×568', telefono320x568, 0, true),
    ]) {
      testWidgets('$nombreTel · barra ${barra.round()} dp · ${teclado ? 'con' : 'sin'} teclado: '
          'sin overflow y la acción asoma (24 dp de su objetivo)', (tester) async {
        final m = await abrirEdicion(tester, tamano: tamano, escala: 3, barraInferior: barra);
        await fallarPorCambio(tester, m, conTeclado: teclado);

        expect(tester.takeException(), isNull, reason: 'sin overflow');
        expect(_visible(tester.getRect(_objetivo), rectZona(tester)), greaterThanOrEqualTo(24));
        final lecturas = m.repo.lecturas;
        // Asoma 24 dp de su objetivo: para tocarla se desplaza la hoja hasta tenerla entera.
        await tester.ensureVisible(_accion);
        await tester.pump();
        await tester.tap(_accion);
        await asentar(tester);
        expect(m.repo.lecturas, lecturas + 1);
      });
    }
  });

  group(
    'QA #321 · la hoja con el teclado abierto no desborda (sin el aviso: lo anterior a #321)',
    () {
      for (final (nombreTel, tamano, escala) in <(String, Size, double)>[
        ('360×640', telefono360x640, 2.0),
        ('320×568', telefono320x568, 1.0),
        ('320×568', telefono320x568, 1.3),
        ('320×568', telefono320x568, 2.0),
        ('360×640', telefono360x640, 3.0),
      ]) {
        testWidgets('$nombreTel · texto ${_x(escala)}: abrir el teclado y escribir el número no '
            'desborda la hoja', (tester) async {
          await abrirEdicion(tester, tamano: tamano, escala: escala);
          await abrirTeclado(tester);
          await tester.enterText(campoNumero, '1238');
          await asentar(tester);

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          // Si ni con el 80 % del cuerpo entra el campo sobre el botón, este pasa al final de lo que se
          // desplaza (#324): se lo alcanza desplazando y queda entero sobre el teclado.
          if (find.descendant(of: zonaDesplazable, matching: botonGuardar).evaluate().isNotEmpty) {
            await tester.ensureVisible(botonGuardar);
            await tester.pump();
          }
          final fijo = tester.getRect(botonGuardar);
          expect(fijo.bottom, lessThanOrEqualTo(tamano.height - tecladoAbierto + .5));
          expect(rectZona(tester).height, greaterThan(0), reason: 'la hoja deja algo que leer');
        });
      }
    },
  );
}
