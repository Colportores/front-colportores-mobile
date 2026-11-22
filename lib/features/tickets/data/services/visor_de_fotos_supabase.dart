import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/visor_de_fotos.dart';
import 'servidor_de_fotos_supabase.dart' show RespuestaDeLaFuncion;

/// [VisorDeFotosDeTicket] sobre la Edge Function `foto-ticket` (acción `ver`; backend-supabase#182).
///
/// Pide `{accion: 'ver', ticketId}` con la sesión del colportor (la función comprueba en la base que
/// el ticket sea suyo) y devuelve el enlace de lectura, que vence a los 5 minutos: no se guarda ni se
/// loguea. `410 foto_vencida` es [FotoVencida] (a los 4 meses la foto ya no está); `404 sin_foto` es
/// [SinFotoParaVer]; sin red o con la función caída, [FotoNoDisponible].
final class VisorDeFotosSupabase implements VisorDeFotosDeTicket {
  VisorDeFotosSupabase(this._pedirEnlace, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase de la app.
  factory VisorDeFotosSupabase.conCliente(SupabaseClient cliente) =>
      VisorDeFotosSupabase((cuerpo) async {
        try {
          final r = await cliente.functions.invoke('foto-ticket', body: cuerpo);
          return (status: r.status, cuerpo: _comoMapa(r.data));
        } on FunctionException catch (e) {
          return (status: e.status, cuerpo: _comoMapa(e.details));
        }
      });

  final Future<RespuestaDeLaFuncion> Function(Map<String, Object?> cuerpo) _pedirEnlace;
  final AppLogger _log;

  @override
  Future<FotoParaVer> ver(String ticketId) async {
    try {
      final r = await _pedirEnlace({'accion': 'ver', 'ticketId': ticketId});
      switch (r.status) {
        case 200:
          final url = r.cuerpo['url'];
          final uri = url is String ? Uri.tryParse(url) : null;
          if (uri == null || !uri.hasScheme) return _fallo(ticketId, 'respuesta_invalida');
          return FotoEnLaNube(uri);
        case 410:
          return const FotoVencida();
        case 404:
          final error = r.cuerpo['error'];
          final codigo = error is Map ? error['codigo'] : null;
          // `sin_foto`: el ticket todavía no tiene foto. `ticket_no_encontrado`: no lo ve esta sesión.
          return codigo == 'sin_foto'
              ? const SinFotoParaVer()
              : _fallo(ticketId, 'ticket_no_encontrado');
        default:
          return _fallo(ticketId, 'servidor_${r.status}');
      }
    } on Object catch (e) {
      if (e is IOException || e is http.ClientException || e is TimeoutException) {
        return _fallo(ticketId, 'red', sinRed: true);
      }
      return _fallo(ticketId, 'inesperado');
    }
  }

  FotoNoDisponible _fallo(String ticketId, String codigo, {bool sinRed = false}) {
    _log.warn(LogModulo.net, 'TICKET_FOTO_VER_FAIL', 'no se pudo pedir la foto de un ticket', {
      'ticket_id': ticketId,
      'codigo': codigo,
    });
    return FotoNoDisponible(sinRed: sinRed);
  }

  static Map<String, Object?> _comoMapa(Object? datos) => datos is Map
      ? {for (final e in datos.entries) '${e.key}': e.value}
      : const <String, Object?>{};
}
