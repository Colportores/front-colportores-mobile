// Los dobles de los tickets (HU-COB-007, #426): el almacén de fotos en memoria, el servidor de fotos
// guionado y un compresor de prueba. Más los constructores de entidades que repiten los tests.
import 'dart:typed_data';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';

/// El instante «ahora» de los tests de tickets.
final ahoraTicket = DateTime.utc(2026, 10, 30, 15, 0, 7, 321);

/// Una foto de prueba de [largo] bytes.
Uint8List fotoDePrueba([int largo = 1000]) =>
    Uint8List.fromList(List.generate(largo, (i) => i % 251));

Ticket ticketDePrueba(
  String id, {
  TipoDeTicket tipo = TipoDeTicket.cobroTarjeta,
  int monto = 150000,
  DateTime? fecha,
  String? autorizacion = '123456',
  TipoDeTarjeta? tarjeta = TipoDeTarjeta.credito,
  String? marca = 'Visa',
  String? urlCloud,
  int syncVersion = 0,
}) => Ticket(
  id: id,
  tipo: tipo,
  montoCentavos: monto,
  fecha: fecha ?? ahoraTicket,
  numeroAutorizacion: autorizacion,
  tarjetaTipo: tarjeta,
  tarjetaMarca: marca,
  urlCloud: urlCloud,
  auditoria: Auditoria(
    createdAt: ahoraTicket,
    updatedAt: ahoraTicket,
    createdBy: 'col-1',
    syncVersion: syncVersion,
  ),
);

FotoLocalDeTicket fotoLocalDePrueba(
  String ticketId, {
  String? ruta,
  EstadoDeSubida estado = EstadoDeSubida.pendiente,
  int bytes = 1000,
}) => FotoLocalDeTicket(
  ticketId: ticketId,
  tipoDeImagen: TipoDeImagen.jpeg,
  bytes: bytes,
  estado: estado,
  creadaEn: ahoraTicket,
  rutaLocal: ruta ?? '/fotos/$ticketId.jpg',
);

/// [AlmacenDeFotosDeTicket] en memoria: guarda los bytes por ruta.
final class AlmacenDeFotosEnMemoria implements AlmacenDeFotosDeTicket {
  final archivos = <String, Uint8List>{};
  Object? fallarAlGuardarCon;
  Object? fallarAlBorrarCon;

  @override
  Future<String> guardar(String ticketId, TipoDeImagen tipo, Uint8List bytes) async {
    final error = fallarAlGuardarCon;
    if (error != null) throw error;
    final ruta = '/fotos/$ticketId.${tipo.extension}';
    archivos[ruta] = bytes;
    return ruta;
  }

  @override
  Future<Uint8List?> leer(String ruta) async => archivos[ruta];

  @override
  Future<void> borrar(String ruta) async {
    final error = fallarAlBorrarCon;
    if (error != null) throw error;
    archivos.remove(ruta);
  }
}

/// [ServidorDeFotosDeTicket] guionado: devuelve las respuestas en orden (la última se repite) y anota
/// qué se le pidió.
final class ServidorDeFotosGuionado implements ServidorDeFotosDeTicket {
  ServidorDeFotosGuionado(this.respuestas);

  final List<ResultadoDeSubidaDeFoto> respuestas;
  final pedidos = <({String ticketId, TipoDeImagen tipo, int bytes})>[];

  /// Si es distinto de `null`, [subir] espera a que se complete (para probar dos pasadas juntas).
  Future<void>? espera;

  @override
  Future<ResultadoDeSubidaDeFoto> subir({
    required String ticketId,
    required TipoDeImagen tipo,
    required Uint8List bytes,
  }) async {
    pedidos.add((ticketId: ticketId, tipo: tipo, bytes: bytes.length));
    await espera;
    final i = pedidos.length - 1;
    return respuestas[i < respuestas.length ? i : respuestas.length - 1];
  }
}

/// [CompresorDeImagen] de prueba: el tamaño de salida depende del paso; `null` si no la puede leer.
final class CompresorDePrueba implements CompresorDeImagen {
  CompresorDePrueba(this.bytesPorPaso, {this.legible = true});

  /// Cuántos bytes devuelve cada llamada, en orden (la última se repite).
  final List<int> bytesPorPaso;
  final bool legible;
  final llamadas = <({int ladoMaximo, int calidad})>[];

  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async {
    llamadas.add((ladoMaximo: ladoMaximo, calidad: calidad));
    if (!legible) return null;
    final i = llamadas.length - 1;
    return fotoDePrueba(bytesPorPaso[i < bytesPorPaso.length ? i : bytesPorPaso.length - 1]);
  }
}
