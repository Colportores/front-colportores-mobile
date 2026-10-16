// La descarga que sigue después de cerrar la app (#300), vista desde la tarjeta de la vista 06
// (HU-SYNC-010, «La descarga sigue después de cerrar la app»). No hay pantalla nueva: la tarjeta
// dice lo de siempre —«Se descarga sola cuando vuelva la señal.» y «Descargando el mapa…»— aunque
// la descarga la haya retomado el descargador al abrir la app, antes de que exista la vista y sin
// poder leer el catálogo.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/descarga_pendiente.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_descargas_arnes.dart';
import '../../helpers/tiles_falsos.dart';

const _seDescargaSola = 'Se descarga sola cuando vuelva la señal.';
const _descargandoMapa = 'Descargando el mapa…';

Finder get _tarjetaSinConexion => find.byKey(ClavesAvisoMapa.sinConexion);
Finder get _tarjetaDatos => find.byKey(ClavesAvisoMapa.datosMoviles);
Finder get _descargar => find.widgetWithText(FilledButton, 'Descargar mapa');
Finder get _descargarConPeso => find.widgetWithText(FilledButton, 'Descargar mapa · 1 MB');

/// Lo que quedó anotado cuando se cerró la app.
DescargaPendiente _anotada(
  PaqueteTiles paquete, {
  bool datosMoviles = true,
  bool pausada = false,
}) => DescargaPendiente(
  paquete: paquete,
  anotadaEn: DateTime.now(),
  permitirDatosMoviles: datosMoviles,
  pausadaPorElColportor: pausada,
);

/// Un disco que no escribe hasta que el test lo deja: la descarga queda «bajando».
Completer<void> _retenerElDisco(ArnesMapa arnes) {
  final compuerta = Completer<void>();
  arnes.archivos.compuerta = compuerta.future;
  addTearDown(() {
    if (!compuerta.isCompleted) compuerta.complete();
  });
  return compuerta;
}

/// La app recién abierta: lo que `ComposicionTiles` hace al arrancar, antes de que haya vista.
Future<void> _abrirApp(ArnesMapa arnes, DescargaPendiente pendiente) async {
  await arnes.repositorio.anotarDescargaPendiente(pendiente);
  await arnes.descargador.retomarPendientes();
}

bool _botonHabilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

void main() {
  setUpAll(cargarFuentesReales);

  group('tarjeta de la vista 06 después de cerrar y abrir la app (#300)', () {
    testWidgets(
      'dado que la app se cerró con el pedido en cola, cuando se abre sin señal y entra a la vista '
      '06, entonces la tarjeta dice que se descarga sola y no ofrece pedirlo otra vez',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));

        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);

        expect(_tarjetaSinConexion, findsOneWidget);
        expect(find.text(_seDescargaSola), findsOneWidget);
        expect(_botonHabilitado(tester, _descargar), isFalse);
        expect(arnes.servidor.pedidos, isEmpty);
      },
    );

    testWidgets(
      'dado que la vista ya estaba abierta cuando el descargador retomó el pedido en cola, '
      'entonces la tarjeta pasa a decir que se descarga sola, aunque sin señal no hay catálogo',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        expect(find.text(_seDescargaSola), findsNothing);
        expect(_botonHabilitado(tester, _descargar), isTrue);

        await _abrirApp(arnes, _anotada(paqueteMontevideo));
        await asentarAviso(tester);

        expect(find.text(_seDescargaSola), findsOneWidget);
        expect(_botonHabilitado(tester, _descargar), isFalse);
      },
    );

    testWidgets(
      'dado que se abre la app sin señal y vuelve la conexión, entonces la descarga arranca sola, '
      'la tarjeta pasa a «Descargando el mapa…» y al terminar el mapa queda descargado',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));
        final compuerta = _retenerElDisco(arnes);
        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        expect(find.text(_seDescargaSola), findsOneWidget);

        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        expect(_tarjetaDatos, findsOneWidget);
        expect(find.text(_descargandoMapa), findsOneWidget);
        expect(find.text(_seDescargaSola), findsNothing);
        expect(_botonHabilitado(tester, _descargarConPeso), isFalse);

        compuerta.complete();
        await asentarAviso(tester);

        expect(arnes.montevideoDescargado, isTrue);
        expect(find.text(_descargandoMapa), findsNothing);
        expect(_tarjetaDatos, findsNothing);
        expect(arnes.repositorio.pendientes, isEmpty);
      },
    );

    testWidgets(
      'dado que se abre la app con datos móviles y la descarga tenía el permiso, entonces sigue '
      'bajando y la tarjeta dice «Descargando el mapa…»',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
        final compuerta = _retenerElDisco(arnes);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));

        await montarAviso(tester, conexion: TipoConexion.datosMoviles, arnes: arnes);

        expect(find.text(_descargandoMapa), findsOneWidget);
        expect(_botonHabilitado(tester, _descargarConPeso), isFalse);

        compuerta.complete();
        await asentarAviso(tester);
        expect(arnes.montevideoDescargado, isTrue);
      },
    );

    testWidgets(
      'dado que se abre la app con datos móviles y la descarga no tenía el permiso, entonces espera '
      'el Wi-Fi y la tarjeta dice que se descarga sola',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo, datosMoviles: false));

        await montarAviso(tester, conexion: TipoConexion.datosMoviles, arnes: arnes);

        expect(find.text(_seDescargaSola), findsOneWidget);
        expect(arnes.servidor.pedidos, isEmpty);

        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await asentarAviso(tester);

        expect(arnes.montevideoDescargado, isTrue);
        expect(find.text(_seDescargaSola), findsNothing);
      },
    );

    testWidgets(
      'dado que el catálogo ya trae otra versión, entonces la tarjeta sigue la descarga que empezó: '
      'termina ese archivo y el mapa queda descargado con la versión de antes',
      (tester) async {
        final nuevo = paqueteDe(
          bytesDePrueba(6000, semilla: 9),
          id: 'ciudad-montevideo',
          nivel: NivelCobertura.ciudad,
          ambitoId: 'c-1',
          version: 'v-nueva',
        );
        final viejo = PaqueteTiles(
          id: paqueteMontevideo.id,
          nivel: paqueteMontevideo.nivel,
          ambitoId: paqueteMontevideo.ambitoId,
          nombre: paqueteMontevideo.nombre,
          version: paqueteMontevideo.version,
          partes: [
            ParteTiles(
              origen: Uri.parse('https://tiles.test/ciudad-montevideo-v1.pmtiles'),
              tamanoBytes: paqueteMontevideo.tamanoBytes,
              sha256: paqueteMontevideo.partes.single.sha256,
            ),
          ],
        );
        final arnes = ArnesMapa(
          conexion: TipoConexion.sinConexion,
          catalogo: [nuevo],
          servirPaqueteMontevideo: false,
        );
        arnes.servidor.archivos[viejo.origen] = bytesDelMapa;
        await _abrirApp(arnes, _anotada(viejo));
        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        expect(find.text(_seDescargaSola), findsOneWidget);

        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        expect(arnes.servidor.origenes.toSet(), {viejo.origen});
        expect(arnes.repositorio.registrados.single.paquete, viejo);
        expect(find.text(_seDescargaSola), findsNothing);
        expect(_tarjetaDatos, findsNothing);
      },
    );

    testWidgets(
      'dado que la descarga retomada falla, entonces el aviso dice qué hacer y el botón vuelve a '
      'estar habilitado: no queda trabado en «Descargando el mapa…»',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));
        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        arnes.servidor.statusError = 500;

        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        expect(find.text(_descargandoMapa), findsNothing);
        expect(find.text(_seDescargaSola), findsNothing);
        expect(find.textContaining('Probá de nuevo'), findsWidgets);
        expect(_botonHabilitado(tester, _descargarConPeso), isTrue);
        expect(arnes.repositorio.pendientes, isEmpty);
      },
    );

    testWidgets(
      'dado que el colportor había pausado la descarga, entonces la tarjeta no dice que se '
      'descarga sola y «Descargar mapa» sigue disponible',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo, pausada: true));

        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await asentarAviso(tester);

        expect(find.text(_seDescargaSola), findsNothing);
        expect(arnes.servidor.pedidos, isEmpty);
        arnes.conectividad.cambiarA(TipoConexion.sinConexion);
        await asentarAviso(tester);
        expect(_botonHabilitado(tester, _descargar), isTrue);
      },
    );

    testWidgets(
      'dado que la descarga en cola se elimina, entonces la tarjeta vuelve a ofrecer «Descargar '
      'mapa» y no queda trabada en «Se descarga sola…»',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));
        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);
        expect(find.text(_seDescargaSola), findsOneWidget);

        await arnes.descargador.eliminar(paqueteMontevideo.id);
        await asentarAviso(tester);

        expect(find.text(_seDescargaSola), findsNothing);
        expect(_botonHabilitado(tester, _descargar), isTrue);
        expect(arnes.repositorio.pendientes, isEmpty);
      },
    );

    testWidgets(
      'dado que salió de la vista y volvió a entrar, entonces la tarjeta sigue diciendo que se '
      'descarga sola',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteMontevideo));
        final montaje = await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);

        await salirYReentrarAviso(tester, montaje);

        expect(find.text(_seDescargaSola), findsOneWidget);
        expect(_botonHabilitado(tester, _descargar), isFalse);
      },
    );

    testWidgets(
      'dado que la descarga de otro lugar quedó pendiente, entonces la tarjeta de este lugar no '
      'dice que se descarga sola',
      (tester) async {
        final arnes = ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]);
        await _abrirApp(arnes, _anotada(paqueteCanelones));

        await montarAviso(tester, conexion: TipoConexion.sinConexion, arnes: arnes);

        expect(find.text(_seDescargaSola), findsNothing);
        expect(_botonHabilitado(tester, _descargar), isTrue);
      },
    );
  });
}
