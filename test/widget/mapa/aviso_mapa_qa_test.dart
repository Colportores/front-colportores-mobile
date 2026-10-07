// QA del PR #291 (#190): los avisos del mapa de la vista 06 (06C·05, 06C·06 y 06C·07) contrastados
// con HU-SYNC-010, HU-UBI-003 y las convenciones de avisos de error (§10). Los tests con `skip`
// documentan un hallazgo de QA: el implementador les saca el `skip` cuando lo arregla.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_descargas_arnes.dart';

const _seDescargaSola = 'Se descarga sola cuando vuelva la señal.';

Finder get _pildora => find.byKey(ClavesAvisoMapa.pildora);
Finder get _tarjetaDatos => find.byKey(ClavesAvisoMapa.datosMoviles);
Finder get _minimizar => find.byTooltip('Minimizar aviso');
Finder get _ahoraNo => find.widgetWithText(TextButton, 'Ahora no');

/// Un disco que no escribe hasta que el test lo deja: la descarga queda «bajando».
Completer<void> _retenerElDisco(ArnesMapa arnes) {
  final compuerta = Completer<void>();
  arnes.archivos.compuerta = compuerta.future;
  addTearDown(() {
    if (!compuerta.isCompleted) compuerta.complete();
  });
  return compuerta;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('QA #190 · avisos del mapa de la vista 06', () {
    group('píldora (06C·06) con el pedido en cola', () {
      testWidgets(
        'dado que la descarga quedó en cola, cuando toca la píldora otra vez con el aviso pasajero '
        'ya cerrado, entonces la app le vuelve a decir que se descarga sola',
        (tester) async {
          await montarAviso(
            tester,
            conexion: TipoConexion.sinConexion,
            catalogo: [paqueteMontevideo],
          );
          await tocarAviso(tester, _minimizar);
          await tocarAviso(tester, _pildora);
          expect(find.text(_seDescargaSola), findsOneWidget);

          // El SnackBar se va solo y la píldora queda igual que antes del toque.
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text(_seDescargaSola), findsNothing);

          await tocarAviso(tester, _pildora);

          expect(find.text(_seDescargaSola), findsOneWidget);
        },
        // skip: issue #190 — QA #190: con el pedido en cola la píldora sigue diciendo «Descargar
        // mapa» y el segundo toque no hace nada ni dice nada (el SnackBar salió una sola vez).
        skip: true,
      );
    });

    group('«Ahora no» del aviso de datos móviles (06C·07)', () {
      testWidgets(
        'dado que ocultó el aviso mientras baja, cuando la descarga falla, entonces algo le dice '
        'que el mapa no se bajó',
        (tester) async {
          final montaje = await montarAviso(
            tester,
            conexion: TipoConexion.datosMoviles,
            catalogo: [paqueteMontevideo],
          );
          final compuerta = _retenerElDisco(montaje.arnes);
          await tocarAviso(tester, find.widgetWithText(FilledButton, 'Descargar mapa · 1 MB'));
          await tocarAviso(tester, _ahoraNo);
          expect(_tarjetaDatos, findsNothing);

          montaje.arnes.archivos.discoLlenoDespuesDe = 1;
          compuerta.complete();
          await asentarAviso(tester);

          expect(montaje.arnes.montevideoDescargado, isFalse);
          expect(find.textContaining('Espacio insuficiente'), findsWidgets);
        },
        // skip: issue #190 — QA #190: tras «Ahora no» la falla de la descarga que el colportor pidió
        // no se muestra en ningún lado (la tarjeta está oculta toda la sesión y no hay SnackBar).
        skip: true,
      );
    });

    group('textos de las fallas del pedido', () {
      testWidgets(
        'dado que el servidor del mapa responde 500, cuando falla la descarga, entonces el aviso '
        'dice qué hacer y no solo qué pasó',
        (tester) async {
          final montaje = await montarAviso(
            tester,
            conexion: TipoConexion.datosMoviles,
            catalogo: [paqueteMontevideo],
          );
          montaje.arnes.servidor.statusError = 500;

          await tocarAviso(tester, find.widgetWithText(FilledButton, 'Descargar mapa · 1 MB'));

          final textos = tester
              .widgetList<Text>(find.descendant(of: _tarjetaDatos, matching: find.byType(Text)))
              .map((texto) => texto.data ?? '')
              .toList();
          final conGuia = RegExp(
            r'(probá|reintentá|intentá|volvé|esperá|revisá)',
            caseSensitive: false,
          );
          expect(textos.where(conGuia.hasMatch), isNotEmpty, reason: textos.join(' | '));
        },
        // skip: issue #190 — QA #190: «El servidor no pudo procesar la solicitud» dice qué pasó pero
        // no qué hacer (convenciones §10); el botón queda a mano, el texto no lo guía.
        skip: true,
      );
    });

    group('sin espacio (HU-SYNC-010)', () {
      testWidgets(
        'dado que el paquete pesa 11 MB y quedan 3 MB libres, cuando toca «Descargar mapa», '
        'entonces dice cuánto falta: «Espacio insuficiente - faltan 8 MB»',
        (tester) async {
          final arnes = ArnesMapa(
            conexion: TipoConexion.datosMoviles,
            catalogo: [paquetePesado(11000000)],
          );
          arnes.espacio.libres = 3000000;
          await montarAviso(tester, arnes: arnes);

          await tocarAviso(tester, find.widgetWithText(FilledButton, 'Descargar mapa · 11 MB'));

          expect(find.textContaining('Espacio insuficiente - faltan 8 MB'), findsOneWidget);
        },
        // skip: issue #190 — QA #190: la HU pide «faltan X MB» con X = peso − espacio libre; hoy dice
        // «se requieren 11 MB» (el peso que falta bajar, sin descontar el espacio libre). Viene de #189.
        skip: true,
      );
    });
  });
}
