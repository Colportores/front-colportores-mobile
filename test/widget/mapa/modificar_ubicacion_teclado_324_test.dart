// Vista 07 «Modificar ubicación» (HU-UBI-004), seguimiento #324 de #307 y #321: con el teclado abierto,
// el campo que se escribe y «Guardar cambios» siguen a la vista, y al volver de «Mover el punto» el
// aviso de tipo queda a la vista.
//
// Lo que se prueba, con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado):
// - Si el campo con foco no entra entero sobre «Guardar cambios», la hoja crece lo justo para que entre,
//   hasta el 80 % del cuerpo, con el botón fijo; si ni así entra, el botón pasa al final de lo que se
//   desplaza. Misma regla que la hoja del alta (`alta_ubicacion_teclado_324_test.dart`).
// - Sin teclado nada cambia: 62 %.
// - Al volver de «Mover el punto» con el aviso de los 2 espacios, el aviso está a la vista.
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show AvisoAlta;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_base_falso.dart' show VistaMapaFalsa;
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';

String _x(double escala) => escala == escala.roundToDouble()
    ? '${escala.round()}×'
    : '${escala.toString().replaceAll('.', ',')}×';

const _avisoDos = 'Esta ubicación tiene 2 espacios. Borralos o reubicalos primero.';

/// El borde de la hoja (su `Material`).
Finder get _hoja =>
    find.ancestor(of: find.byType(HojaModificarDatos), matching: find.byType(Material)).first;

bool _enLoQueSeDesplaza(Finder f) =>
    find.descendant(of: zonaDesplazable, matching: f).evaluate().isNotEmpty;

/// Cuánto del alto de [r] queda fuera de [zona] o detrás del botón fijo [boton].
double _corte(Rect r, Rect zona, Rect boton) {
  final limite = zona.bottom < boton.top ? zona.bottom : boton.top;
  return (zona.top - r.top).clamp(0, double.infinity) +
      (r.bottom - limite).clamp(0, double.infinity);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.pump();
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentar(tester);
}

void main() {
  setUpAll(cargarFuentesReales);

  final telefonos = <(String, Size, double)>[
    ('360×640', telefono360x640, tecladoAbierto),
    ('412×915', const Size(412, 915), 340),
    ('320×568', telefono320x568, tecladoAbierto),
  ];

  group(
    '#324 · 07 · con el teclado abierto, el campo que se escribe y «Guardar cambios» siguen a la '
    'vista',
    () {
      for (final (nombreTel, tamano, teclado) in telefonos) {
        for (final escala in [1.0, 1.3, 2.0, 3.0]) {
          testWidgets('07·01 Editar datos · $nombreTel · texto ${_x(escala)} · teclado de '
              '${teclado.round()} dp: escribir el número y la calle los deja enteros, el botón '
              'entero y la hoja no pasa del 80 %', (tester) async {
            await abrirEdicion(tester, tamano: tamano, escala: escala);
            await abrirTeclado(tester, alto: teclado);
            final cuerpo = tamano.height - teclado;
            expect(tester.takeException(), isNull, reason: 'sin overflow al abrir el teclado');

            for (final (campo, nombre, valor) in <(Finder, String, String)>[
              (campoNumero, 'número', '1238'),
              (find.byType(TextField).first, 'calle', 'Avenida Italia'),
            ]) {
              await tester.enterText(campo, valor);
              await asentar(tester);
              final hoja = tester.getRect(_hoja);
              expect(
                hoja.height,
                lessThanOrEqualTo(cuerpo * .8 + .5),
                reason: 'escribiendo la $nombre: la hoja pasa del 80 % del cuerpo ($hoja)',
              );
              expect(hoja.height, greaterThanOrEqualTo(cuerpo * .62 - .5));
              expect(hoja.bottom, closeTo(cuerpo, .5), reason: 'la hoja apoya en el teclado');
              expect(
                _corte(tester.getRect(campo), rectZona(tester), tester.getRect(botonGuardar)),
                lessThanOrEqualTo(1),
                reason: 'escribiendo la $nombre se corta el campo',
              );
              expect(find.widgetWithText(TextField, valor), findsOneWidget);
              expect(tester.takeException(), isNull, reason: 'escribiendo la $nombre: overflow');
            }

            // El botón, fijo o al final de lo que se desplaza, se alcanza entero sobre el teclado.
            if (_enLoQueSeDesplaza(botonGuardar)) {
              await tester.ensureVisible(botonGuardar);
              await tester.pump();
            }
            final boton = tester.getRect(botonGuardar);
            expect(boton.top, greaterThanOrEqualTo(0));
            expect(
              boton.bottom,
              lessThanOrEqualTo(cuerpo + .5),
              reason: '«Guardar cambios» tapado',
            );
            expect(botonGuardar.hitTestable(), findsOneWidget);
            expect(find.text(TextosModificar.darDeBaja), findsNothing, reason: 'con el teclado no');
          });
        }
      }
    },
  );

  group('#324 · 07 · cuánto crece la hoja y dónde queda «Guardar cambios»', () {
    for (final (nombreTel, tamano, _) in telefonos) {
      testWidgets('$nombreTel · sin teclado la hoja ocupa el 62 % del cuerpo', (tester) async {
        await abrirEdicion(tester, tamano: tamano);
        expect(tester.getRect(_hoja).height, lessThanOrEqualTo(tamano.height * .62 + .5));
      });
    }

    testWidgets('320×568 · 1×: con el teclado la hoja crece más allá del 62 % para que el campo '
        'entre entero sobre «Guardar cambios»', (tester) async {
      await abrirEdicion(tester, tamano: telefono320x568);
      await abrirTeclado(tester);
      const cuerpo = 568 - tecladoAbierto;

      expect(tester.getRect(_hoja).height, greaterThan(cuerpo * .62 + 1));
      expect(tester.getRect(_hoja).height, lessThanOrEqualTo(cuerpo * .8 + .5));
      expect(_enLoQueSeDesplaza(botonGuardar), isFalse, reason: 'el botón sigue fijo');
    });

    testWidgets('texto al 300 %: con el teclado «Guardar cambios» pasa al final de lo que se '
        'desplaza y la hoja no desborda ni pasa del 80 %', (tester) async {
      await abrirEdicion(tester, tamano: telefono320x568, escala: 3);
      await abrirTeclado(tester);
      const cuerpo = 568 - tecladoAbierto;
      await tester.enterText(campoNumero, '1238');
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(_hoja).height, closeTo(cuerpo * .8, .5));
      expect(_enLoQueSeDesplaza(botonGuardar), isTrue, reason: 'el botón va al final');
      expect(
        _corte(tester.getRect(campoNumero), rectZona(tester), const Rect.fromLTWH(0, 9999, 1, 1)),
        lessThanOrEqualTo(1),
        reason: 'el campo se ve entero',
      );
      await tester.ensureVisible(botonGuardar);
      await tester.pump();
      expect(tester.getRect(botonGuardar).bottom, lessThanOrEqualTo(cuerpo + .5));
      expect(botonGuardar.hitTestable(), findsOneWidget);
    });

    testWidgets('al cerrar el teclado «Guardar cambios» vuelve a quedar fijo al pie, donde '
        'estaba', (tester) async {
      await abrirEdicion(tester, tamano: telefono320x568, escala: 3);
      final antes = tester.getRect(botonGuardar);
      await abrirTeclado(tester);
      expect(_enLoQueSeDesplaza(botonGuardar), isTrue);
      await cerrarTeclado(tester);

      expect(_enLoQueSeDesplaza(botonGuardar), isFalse);
      expect(tester.getRect(botonGuardar), antes);
      expect(tester.takeException(), isNull);
    });

    for (final escala in [1.15, 1.3, 2.0]) {
      testWidgets('360×640 · texto ${_x(escala)}: con el teclado el botón mide más de 52 dp y el '
          'campo no se corta', (tester) async {
        await abrirEdicion(tester, escala: escala);
        await abrirTeclado(tester);
        await tester.enterText(campoNumero, '1238');
        await asentar(tester);

        expect(tester.getSize(botonGuardar).height, greaterThanOrEqualTo(52));
        expect(tester.takeException(), isNull);
        expect(
          _corte(tester.getRect(campoNumero), rectZona(tester), tester.getRect(botonGuardar)),
          lessThanOrEqualTo(1),
        );
      });
    }
  });

  group('#324 · 07 · al volver de «Mover el punto» el aviso de tipo queda a la vista', () {
    for (final (nombreTel, tamano, escala, barra) in <(String, Size, double, double)>[
      ('320×568', telefono320x568, 2.0, 0),
      ('320×568', telefono320x568, 2.0, barraDeTresBotones),
      ('360×640', telefono360x640, 2.0, 0),
      ('360×640', telefono360x640, 1.0, 0),
    ]) {
      testWidgets('$nombreTel · texto ${_x(escala)} · barra ${barra.round()} dp: llega el 2.º '
          'depto con «Mover el punto» abierto, al cancelar el aviso está dentro de lo que se '
          'desplaza', (tester) async {
        final m = await abrirEdicion(
          tester,
          tamano: tamano,
          escala: escala,
          barraInferior: barra,
          repo: RepoEdicionFalso(
            ubicacionGuardada(tipo: TipoUbicacion.edificio),
            espacios: 1,
            numeroDepto: '3B',
          ),
        );
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, find.text(TextosModificar.moverElPunto));

        m.repo.cambiarEspacios(2);
        await asentar(tester);
        await _tocar(tester, find.text(TextosModificar.cancelar));

        expect(tester.takeException(), isNull);
        final aviso = find.text(_avisoDos);
        expect(aviso, findsOneWidget);
        final zona = rectZona(tester);
        // La tarjeta entera (con la letra de prueba el aviso puede ser más alto que la zona): entra
        // entera o, si no entra, se la empieza a leer desde arriba.
        final r = tester.getRect(find.ancestor(of: aviso, matching: find.byType(AvisoAlta)).first);
        final visible = r.bottom.clamp(zona.top, zona.bottom) - r.top.clamp(zona.top, zona.bottom);
        expect(
          visible,
          greaterThanOrEqualTo((r.height < zona.height ? r.height : zona.height) - 1),
          reason: 'el aviso se lee entero (o tanto como entra en la zona): $r en $zona',
        );
        expect(tester.getRect(aviso).bottom, greaterThan(zona.top), reason: 'no queda arriba');
        expect(tester.getRect(aviso).top, lessThan(zona.bottom), reason: 'ni abajo');
        expect(tester.widget<FilledButton>(botonGuardar).onPressed, isNull);
      });
    }

    testWidgets('sin aviso al volver de «Mover el punto» la hoja queda donde estaba', (
      tester,
    ) async {
      await abrirEdicion(tester, tamano: telefono320x568, escala: 2);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, find.text(TextosModificar.moverElPunto));
      await _tocar(tester, find.text(TextosModificar.cancelar));

      expect(tester.takeException(), isNull);
      expect(find.text(_avisoDos), findsNothing);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: zonaDesplazable, matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.pixels, 0);
    });
  });

  group('#324 · 07·02 «Mover el punto» · los rótulos no se llevan el arrastre del mapa', () {
    // Los rótulos van pintados encima del mapa y llevan un `SingleChildScrollView` (para recortarse con
    // el teclado). Un `Scrollable` se queda con el puntero en todo su rectángulo aunque no se
    // desplace: sin `IgnorePointer` esa franja de arriba (de 100 a 125 dp, según el teléfono y el
    // texto) quedaba muerta para el mapa. Con el texto grande el mapa empieza más abajo (los rótulos
    // lo hacen bajar para no tapar el pin): ahí se arrastra desde 4 dp debajo de su borde de arriba.
    for (final (nombreTel, tamano) in <(String, Size)>[
      ('360×640', telefono360x640),
      ('412×915', const Size(412, 915)),
    ]) {
      for (final escala in [1.0, 2.0, 3.0]) {
        for (final y in [60.0, 100.0]) {
          testWidgets('$nombreTel · texto ${_x(escala)}: arrastrar el mapa desde y = ${y.round()} '
              '(o desde su borde de arriba, si empieza más abajo) mueve la cámara', (tester) async {
            final montada = await abrirEdicion(tester, tamano: tamano, escala: escala);
            await tester.tap(find.text(TextosModificar.moverElPunto));
            await asentar(tester);
            expect(find.text(TextosModificar.tituloMover), findsOneWidget);

            final mapa = tester.getRect(find.byType(VistaMapaFalsa));
            final desde = Offset(tamano.width - 30, y < mapa.top + 4 ? mapa.top + 4 : y);
            expect(desde.dy, lessThan(mapa.bottom), reason: 'el punto $desde está sobre el mapa');
            final antes = montada.mapa.camara!.centro;
            await tester.dragFrom(desde, const Offset(-60, 0));
            await asentar(tester);

            expect(
              montada.mapa.camara!.centro.lon,
              isNot(closeTo(antes.lon, 1e-9)),
              reason: 'el arrastre desde $desde no llegó al mapa ($mapa)',
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
