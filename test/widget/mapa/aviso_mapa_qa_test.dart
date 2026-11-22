// QA del PR #291 (#190): los avisos del mapa de la vista 06 (06C·05, 06C·06 y 06C·07) contrastados
// con HU-SYNC-010, HU-UBI-003 y las convenciones de avisos de error (§10). Cada test es un hallazgo
// de la ronda 1 de QA; nacieron con `skip` y pasan desde que se arregló cada uno.
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
      );
    });
  });
}
