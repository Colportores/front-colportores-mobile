// Arnés de los tests de «Foto del ticket de tarjeta» (vista 29, grupo C, HU-COB-007, #427): la cámara
// de prueba, un repositorio de tickets en memoria que sigue las reglas del real (idempotente por id,
// «Borrar copia» solo con la foto subida) con la subida que el test maneja, y la pantalla montada con
// un botón que abre `FlujoTicketDeTarjeta.abrir`.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/flujo_ticket_de_tarjeta.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show MonitorConectividad, TipoConexion;
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'tickets_falsos.dart';

/// El hoy del canvas: viernes 23/10/2026, mediodía en Montevideo.
final hoyDelTicket = DateTime.utc(2026, 10, 23, 15);

/// La cámara y la galería de prueba: cada llamada toma la siguiente respuesta (la última se repite).
final class CapturadorDePrueba implements CapturadorDeFoto {
  CapturadorDePrueba({List<ResultadoDeCaptura>? camara, List<ResultadoDeCaptura>? galeria})
    : camara = camara ?? [FotoCapturada(fotoDePrueba(4000))],
      galeria = galeria ?? [FotoCapturada(fotoDePrueba(4000))];

  final List<ResultadoDeCaptura> camara;
  final List<ResultadoDeCaptura> galeria;
  var vecesCamara = 0;
  var vecesGaleria = 0;
  var vecesAjustes = 0;

  /// Si no es `null`, la cámara y la galería esperan a que se complete (una captura «en curso»).
  Completer<void>? compuerta;

  /// Si no es `null`, la próxima llamada lanza esto.
  Object? lanzar;

  ResultadoDeCaptura _siguiente(List<ResultadoDeCaptura> l, int veces) =>
      l[veces - 1 < l.length ? veces - 1 : l.length - 1];

  @override
  Future<ResultadoDeCaptura> sacarFoto() async {
    vecesCamara++;
    final veces = vecesCamara;
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    return _siguiente(camara, veces);
  }

  @override
  Future<ResultadoDeCaptura> elegirDeLaGaleria() async {
    vecesGaleria++;
    final veces = vecesGaleria;
    await compuerta?.future;
    return _siguiente(galeria, veces);
  }

  @override
  Future<void> abrirLosAjustes() async => vecesAjustes++;
}

/// [TicketRepository] en memoria con las reglas del real. El test mueve el estado de la subida con
/// [cambiar]; [fotosPorSubir], [marcarFotoSubida] y [anotarIntentoFallido] hacen lo mismo que la cola
/// de verdad, así «Reintentar ahora» se prueba con la subida real.
final class TicketsEnMemoria implements TicketRepository {
  TicketRegistrado? actual;
  final _cambios = StreamController<TicketRegistrado?>.broadcast();

  /// Cada ticket que le llegó a [registrar], también los que fallaron.
  final recibidos = <({Ticket ticket, Uint8List foto, String? cobroId})>[];

  /// Cada [registrar] toma la siguiente (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [registrar] espera a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, el próximo [registrar] lanza esto.
  Object? lanzar;

  /// Si no es `null`, [borrarCopiaLocal] responde con esta falla.
  Failure? fallaAlBorrar;
  var borrados = 0;

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) async {
    recibidos.add((ticket: ticket, foto: foto, cobroId: cobroId));
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final previo = actual;
    if (previo != null && previo.ticket.id == ticket.id) {
      return Right(TicketRegistrado(ticket: previo.ticket, foto: previo.foto, yaEstaba: true));
    }
    final nuevo = TicketRegistrado(
      ticket: ticket,
      foto: FotoLocalDeTicket(
        ticketId: ticket.id,
        tipoDeImagen: tipoDeImagen,
        bytes: foto.length,
        estado: EstadoDeSubida.pendiente,
        creadaEn: ticket.auditoria.createdAt,
        rutaLocal: '/fotos/${ticket.id}.jpg',
      ),
    );
    _poner(nuevo);
    return Right(nuevo);
  }

  void _poner(TicketRegistrado nuevo) {
    actual = nuevo;
    _cambios.add(nuevo);
  }

  /// Mueve el estado del ticket guardado: lo que haría el motor, la cola o el servidor.
  void cambiar({
    EstadoDeSubida? estado,
    String? ultimoError,
    bool quitarElError = false,
    String? urlCloud,
    DateTime? subidoEn,
    String? campaniaValidadoraId,
    bool sinCopia = false,
    int? intentos,
  }) {
    final r = actual!;
    final t = r.ticket;
    final ticket = Ticket(
      id: t.id,
      tipo: t.tipo,
      montoCentavos: t.montoCentavos,
      fecha: t.fecha,
      auditoria: t.auditoria,
      numeroAutorizacion: t.numeroAutorizacion,
      tarjetaTipo: t.tarjetaTipo,
      tarjetaMarca: t.tarjetaMarca,
      urlCloud: urlCloud ?? t.urlCloud,
      estado: t.estado,
      campaniaValidadoraId: campaniaValidadoraId ?? t.campaniaValidadoraId,
      subidoEn: subidoEn ?? t.subidoEn,
    );
    final foto = r.foto.copyWith(
      estado: estado,
      ultimoError: quitarElError ? null : (ultimoError ?? r.foto.ultimoError),
      intentos: intentos,
      rutaLocal: sinCopia ? null : r.foto.rutaLocal,
    );
    _poner(TicketRegistrado(ticket: ticket, foto: foto));
  }

  @override
  Stream<TicketRegistrado?> observarTicket(String ticketId) async* {
    yield actual;
    yield* _cambios.stream;
  }

  @override
  Future<Either<Failure, List<FotoPorSubir>>> fotosPorSubir() async {
    final r = actual;
    if (r == null || r.foto.estado != EstadoDeSubida.pendiente || !r.foto.hayCopiaLocal) {
      return const Right([]);
    }
    return Right([FotoPorSubir(ticket: r.ticket, foto: r.foto)]);
  }

  @override
  Stream<int> cantidadDeFotosPorSubir() => const Stream.empty();

  @override
  Future<Either<Failure, Uint8List?>> bytesDeLaFoto(String ticketId) async =>
      Right(recibidos.isEmpty ? fotoDePrueba() : recibidos.last.foto);

  @override
  Future<Either<Failure, Ticket>> marcarFotoSubida(String ticketId, String ruta) async {
    cambiar(estado: EstadoDeSubida.subida, urlCloud: ruta, quitarElError: true);
    return Right(actual!.ticket);
  }

  @override
  Future<Either<Failure, Unit>> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  }) async {
    cambiar(
      estado: definitivo ? EstadoDeSubida.rechazada : null,
      ultimoError: codigo,
      intentos: actual!.foto.intentos + 1,
    );
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> borrarCopiaLocal(String ticketId) async {
    final falla = fallaAlBorrar;
    if (falla != null) return Left(falla);
    if (actual!.foto.estado != EstadoDeSubida.subida) {
      return const Left(FailureTicketCopiaSinSubir());
    }
    borrados++;
    cambiar(sinCopia: true);
    return const Right(unit);
  }

  @override
  Stream<Set<String>> cobrosConTicketPendiente() => const Stream.empty();
}

/// La conexión del teléfono de prueba.
final class ConexionDePrueba implements MonitorConectividad {
  TipoConexion tipo = TipoConexion.wifi;
  final _cambios = StreamController<TipoConexion>.broadcast();

  void cambiarA(TipoConexion nuevo) {
    tipo = nuevo;
    _cambios.add(nuevo);
  }

  @override
  Future<TipoConexion> actual() async => tipo;

  @override
  Stream<TipoConexion> get cambios => _cambios.stream;
}

/// El cobro con tarjeta del canvas: $ 1.200, crédito Visa, aprobación 004512, del 23/10.
Cobranza cobroConTarjeta({
  String id = 'cobro-1',
  int monto = 120000,
  TipoTarjeta? tipo = TipoTarjeta.credito,
  String? marca = 'Visa',
  String? aprobacion = '004512',
}) => Cobranza(
  id: id,
  ventaId: 'v-42',
  montoCentavos: monto,
  medio: MedioCobranza.tarjeta,
  fecha: hoyDelTicket,
  tarjetaTipo: tipo,
  tarjetaMarca: marca,
  numeroAprobacion: aprobacion,
  auditoria: Auditoria(createdAt: hoyDelTicket, updatedAt: hoyDelTicket, createdBy: 'col-1'),
);

class ArnesTicket {
  ArnesTicket({
    required this.repo,
    required this.capturador,
    required this.compresor,
    required this.servidor,
    required this.conexion,
    required this.ahora,
  });

  final TicketsEnMemoria repo;
  final CapturadorDePrueba capturador;
  final CompresorDePrueba compresor;
  final ServidorDeFotosGuionado servidor;
  final ConexionDePrueba conexion;
  DateTime ahora;

  /// Los ids de ticket que se generaron, en orden.
  final idsGenerados = <String>[];

  /// Lo que devolvió cada `FlujoTicketDeTarjeta.abrir` terminado.
  final resultados = <ResultadoDelFlujoDeTicket>[];
}

/// Un arnés con los dobles por defecto: cámara que saca una foto, compresor que entra en 200 KB y
/// subida que falla por la red.
ArnesTicket nuevoArnesTicket({
  TicketsEnMemoria? repo,
  CapturadorDePrueba? capturador,
  CompresorDePrueba? compresor,
  ServidorDeFotosGuionado? servidor,
}) => ArnesTicket(
  repo: repo ?? TicketsEnMemoria(),
  capturador: capturador ?? CapturadorDePrueba(),
  compresor: compresor ?? CompresorDePrueba([150 * 1024]),
  servidor:
      servidor ?? ServidorDeFotosGuionado([const SubidaFallida(codigo: 'red', reintentable: true)]),
  conexion: ConexionDePrueba(),
  ahora: hoyDelTicket,
);

/// Lo que hay que reemplazar para que la foto del ticket funcione con los dobles de [arnes].
List<Override> overridesDeTicket(
  ArnesTicket arnes, {
  bool conCamara = true,
  bool conConexion = true,
}) => [
  ticketRepositoryProvider.overrideWithValue(arnes.repo),
  if (conCamara) capturadorDeFotoProvider.overrideWithValue(arnes.capturador),
  compresorDeImagenProvider.overrideWithValue(arnes.compresor),
  servidorDeFotosDeTicketProvider.overrideWithValue(arnes.servidor),
  if (conConexion) monitorConectividadProvider.overrideWithValue(arnes.conexion),
  generadorIdTicketProvider.overrideWithValue(() {
    final id = 'tk-${arnes.idsGenerados.length + 1}';
    arnes.idsGenerados.add(id);
    return id;
  }),
  relojTicketProvider.overrideWithValue(() => arnes.ahora),
];

/// Monta una pantalla con el botón «abrir ticket» y, si [abrir], lo toca.
Future<ArnesTicket> montarTicket(
  WidgetTester tester, {
  TicketsEnMemoria? repo,
  CapturadorDePrueba? capturador,
  CompresorDePrueba? compresor,
  ServidorDeFotosGuionado? servidor,
  Cobranza? cobro,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = nuevoArnesTicket(
    repo: repo,
    capturador: capturador,
    compresor: compresor,
    servidor: servidor,
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final cobroAbierto = cobro ?? cobroConTarjeta();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDeTicket(arnes),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await FlujoTicketDeTarjeta.abrir(
                    context,
                    cobro: cobroAbierto,
                    colportorId: 'col-1',
                    subtitulo: 'María Fernández · Mataojo 2044 · 3B',
                  );
                  arnes.resultados.add(r);
                },
                child: const Text('abrir ticket'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirTicket(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura de la pantalla.
Future<void> abrirTicket(WidgetTester tester) async {
  await tester.tap(find.text('abrir ticket'));
  await asentarAgendar(tester);
}

final paginaTicket = find.byKey(const Key('ticket_pagina'));
final botonPrincipal = find.byKey(const Key('venta_cta'));
final atrasTicket = find.byKey(const Key('venta_atras'));
final campoMontoTicket = find.descendant(
  of: find.byKey(const Key('ticket_monto')),
  matching: find.byType(TextField),
);
final campoAutorizacion = find.descendant(
  of: find.byKey(const Key('ticket_autorizacion')),
  matching: find.byType(TextField),
);

/// El botón principal de abajo, como `FilledButton`.
FilledButton elBotonPrincipal(WidgetTester tester) => tester.widget<FilledButton>(botonPrincipal);

/// Trae [f] a la vista: la lista es perezosa y con letra grande el widget puede no estar armado.
Future<void> traerTicketAlAlcance(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final lista = find.descendant(of: paginaTicket, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(f, 100, scrollable: lista.first);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

Future<void> tocarTicket(WidgetTester tester, Finder f) async {
  await traerTicketAlAlcance(tester, f);
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

/// Saca la foto y llega a la vista previa (29C-02).
Future<void> sacarLaFoto(WidgetTester tester) async {
  await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));
}

/// Llega al paso «Datos del ticket».
Future<void> irALosDatos(WidgetTester tester) async {
  await sacarLaFoto(tester);
  await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));
}

/// Llega a la pantalla de después de guardar (el ticket ya está registrado).
Future<void> enviarElTicket(WidgetTester tester) async {
  await irALosDatos(tester);
  await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));
}
