// Arnés del QA de «Mis tickets» y del detalle de un ticket (vista 38B, HU-COB-009, #388): los estados a
// los que una persona puede llegar, los teléfonos de la matriz, las fuentes reales y las capturas.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/services/visor_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cuenta_arnes.dart';
import 'deposito_arnes.dart';
import 'historial_tickets_arnes.dart';
import 'qa_vista33_deposito_443_arnes.dart' show cargarFuentes443;

export 'cuenta_arnes.dart';
export 'deposito_arnes.dart';
export 'historial_tickets_arnes.dart';
export 'qa_vista33_deposito_443_arnes.dart' show usarFuentesReales443;

const conCapturas388 = bool.fromEnvironment('QA_CAPTURAS');

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const tamanos388 = [t360x640, t412x915];
const escalas388 = [1.0, 2.0];

String sufijo388(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Una captura PNG en `.dart_tool/qa_capturas/388_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar388(WidgetTester tester, String nombre) async {
  if (!conCapturas388) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/388_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Un PNG de 1×1 de verdad: una foto que el decodificador acepta.
final fotoPng388 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Un visor que no contesta hasta que el test lo suelta (la foto «Cargando»).
final class VisorLento388 implements VisorDeFotosDeTicket {
  final espera = Completer<FotoParaVer>();
  @override
  Future<FotoParaVer> ver(String ticketId) => espera.future;
}

/// Los estados de «Mis tickets» y del detalle a los que una persona puede llegar.
enum Estado388 {
  cargando,
  vacio,
  historial,
  filtroSinResultados,
  sinConexion,
  sinConexionSinBajada,
  error,
  sesenta,
  motivoLargo,
  rechazado,
  rechazadoSinMotivo,
  validado,
  retiroValidado,
  porValidar,
  enCola,
  fotoLocal,
  fotoVencida,
  fotoSinRed,
  fotoNoDisponible,
  fotoSinEnviar,
  fotoRechazada,
  fotoCargando,
  cuentaConLaFila,
  listaConDevuelto,
  detalleDevuelto,
}

const _motivoLargo =
    'La foto no se lee porque está movida, cortada por abajo y con el número de autorización tapado '
    'por un dedo; sacá otra con buena luz, sin sombras, apoyando el ticket sobre una mesa plana';

final _hoy = hoyDelHistorial;

ItemDelHistorial _fotoDeNube(String id, {bool subida = true}) =>
    itemDePrueba(id, fotoSubida: subida, hayCopiaLocal: false);

/// Un pago de alquiler que el coordinador validó y después devolvió (`anulado_at`, #388 23/11).
ItemDelHistorial _devuelto() => itemDePrueba(
  'dv',
  fecha: DateTime.utc(2026, 10, 12, 15),
  pesos: 3000,
  concepto: ConceptoDeDeposito.alquiler,
  estado: EstadoDelItem.devuelto,
);

/// Lo que el estado necesita para armar el historial, la pantalla del arnés y el visor.
({HistorialControlable repo, ArnesDeDeposito arnes, VisorDeFotosDeTicket visor, String? abrirFila})
_receta(Estado388 e) {
  var arnes = ArnesDeDeposito();
  VisorDeFotosDeTicket visor = VisorGuionado();
  String? abrir;
  HistorialControlable repo;
  switch (e) {
    case Estado388.cargando:
      repo = HistorialControlable();
    case Estado388.vacio:
      repo = HistorialControlable(inicial: historialCon(const []));
    case Estado388.historial || Estado388.filtroSinResultados || Estado388.cuentaConLaFila:
      repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
    case Estado388.sinConexion:
      arnes = ArnesDeDeposito(conexion: TipoConexion.sinConexion);
      repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba('d0', estado: EstadoDelItem.enCola),
          ...filasDelCanvas().skip(2),
        ]),
      );
    case Estado388.sinConexionSinBajada:
      arnes = ArnesDeDeposito(conexion: TipoConexion.sinConexion);
      repo = HistorialControlable(
        inicial: HistorialDeTickets(items: filasDelCanvas(), bajadoEn: null),
      );
    case Estado388.error:
      repo = HistorialControlable()..fallaAlSuscribir = true;
    case Estado388.sesenta:
      repo = HistorialControlable(
        inicial: historialCon([
          for (var i = 0; i < 60; i++)
            itemDePrueba(
              'm$i',
              fecha: _hoy.subtract(Duration(days: i)),
              pesos: 100 + i,
              estado: EstadoDelItem.values[i % 4],
              motivo: i % 4 == 2 ? 'No se lee $i' : null,
            ),
        ]),
      );
    case Estado388.motivoLargo:
      repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba(
            'd2',
            estado: EstadoDelItem.rechazado,
            motivo: _motivoLargo,
            pesos: 12345678,
          ),
        ]),
      );
      abrir = 'd2';
    case Estado388.rechazado:
      repo = HistorialControlable(
        inicial: historialCon([
          itemDePrueba(
            'd2',
            fecha: DateTime.utc(2026, 10, 20, 15),
            pesos: 2000,
            estado: EstadoDelItem.rechazado,
            motivo: 'La foto no se lee',
            autorizacion: '003981',
            tarjeta: null,
          ),
        ]),
      );
      abrir = 'd2';
    case Estado388.rechazadoSinMotivo:
      repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d2', estado: EstadoDelItem.rechazado)]),
      );
      abrir = 'd2';
    case Estado388.validado:
      repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
      abrir = 'd4';
    case Estado388.retiroValidado:
      repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
      abrir = 'd3';
    case Estado388.porValidar:
      repo = HistorialControlable(inicial: historialCon(filasDelCanvas()));
      abrir = 'd1';
    case Estado388.enCola:
      repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d0', estado: EstadoDelItem.enCola)]),
      );
      abrir = 'd0';
    case Estado388.fotoLocal:
      arnes.tickets.fotosLocales['t-d1'] = fotoPng388;
      repo = HistorialControlable(inicial: historialCon([itemDePrueba('d1')]));
      abrir = 'd1';
    case Estado388.fotoVencida:
      visor = VisorGuionado([const FotoVencida()]);
      repo = HistorialControlable(inicial: historialCon([_fotoDeNube('d1')]));
      abrir = 'd1';
    case Estado388.fotoSinRed:
      visor = VisorGuionado([const FotoNoDisponible(sinRed: true)]);
      repo = HistorialControlable(inicial: historialCon([_fotoDeNube('d1')]));
      abrir = 'd1';
    case Estado388.fotoNoDisponible:
      visor = VisorGuionado([const FotoNoDisponible()]);
      repo = HistorialControlable(inicial: historialCon([_fotoDeNube('d1')]));
      abrir = 'd1';
    case Estado388.fotoSinEnviar:
      visor = VisorGuionado([const SinFotoParaVer()]);
      repo = HistorialControlable(inicial: historialCon([_fotoDeNube('d1', subida: false)]));
      abrir = 'd1';
    case Estado388.fotoRechazada:
      visor = VisorGuionado([const SinFotoParaVer()]);
      repo = HistorialControlable(
        inicial: historialCon([itemDePrueba('d1', hayCopiaLocal: false, fotoRechazada: true)]),
      );
      abrir = 'd1';
    case Estado388.fotoCargando:
      visor = VisorLento388();
      repo = HistorialControlable(inicial: historialCon([_fotoDeNube('d1')]));
      abrir = 'd1';
    case Estado388.listaConDevuelto:
      repo = HistorialControlable(inicial: historialCon([...filasDelCanvas(), _devuelto()]));
    case Estado388.detalleDevuelto:
      repo = HistorialControlable(inicial: historialCon([_devuelto()]));
      abrir = 'dv';
  }
  return (repo: repo, arnes: arnes, visor: visor, abrirFila: abrir);
}

/// Lo que el test necesita para soltar y consultar lo que armó el estado.
typedef Armado388 = ({
  HistorialControlable repo,
  ArnesDeDeposito arnes,
  VisorDeFotosDeTicket visor,
});

/// Monta la pantalla y la deja en [estado] con las fuentes reales.
Future<Armado388> llegarA388(
  WidgetTester tester,
  Estado388 estado, {
  Size tamano = t360x640,
  double escala = 1,
}) async {
  await cargarFuentes443(tester);
  final r = _receta(estado);
  if (estado == Estado388.cuentaConLaFila) {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await montarCuenta(
      tester,
      r.arnes.cuenta,
      tamano: tamano,
      escala: escala,
      overrides: [
        ...r.arnes.overridesSinCuenta,
        historialDeTicketsRepositoryProvider.overrideWithValue(r.repo),
      ],
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cuenta_mis_tickets')));
    await tester.pump();
    return (repo: r.repo, arnes: r.arnes, visor: r.visor);
  }
  await montarHistorial(
    tester,
    r.repo,
    arnes: r.arnes,
    visor: r.visor,
    tamano: tamano,
    escala: escala,
  );
  switch (estado) {
    case Estado388.filtroSinResultados:
      await tester.tap(find.byKey(const Key('tickets_filtro_rechazados')));
      await tester.pumpAndSettle();
      // El canvas trae un rechazado: para llegar al «sin resultados» se filtra lo que no hay.
      r.repo.emitir(historialCon(filasDelCanvas().where((i) => i.id != 'd2').toList()));
      await tester.pumpAndSettle();
    case Estado388.cargando:
      break;
    default:
      final abrir = r.abrirFila;
      if (abrir != null) {
        await tester.scrollUntilVisible(
          fila(abrir),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('tickets_lista')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(fila(abrir));
        await tester.pump();
        await tester.tapAt(tester.getTopLeft(fila(abrir)) + const Offset(30, 30));
        // La foto «Cargando» gira sin parar: ahí no se espera a que se quede quieto.
        if (estado == Estado388.fotoCargando) {
          await tester.pump(const Duration(milliseconds: 500));
        } else {
          await tester.pumpAndSettle();
        }
      }
  }
  return (repo: r.repo, arnes: r.arnes, visor: r.visor);
}

/// Suelta lo que quedó esperando y deja el árbol quieto.
Future<void> soltar388(WidgetTester tester, Armado388 a) async {
  final visor = a.visor;
  if (visor is VisorLento388 && !visor.espera.isCompleted) {
    visor.espera.complete(const FotoVencida());
  }
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}
