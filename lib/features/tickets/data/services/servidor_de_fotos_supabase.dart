import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/ticket.dart';
import '../../domain/services/puertos_de_fotos.dart';

/// Lo que contestó la Edge Function `foto-ticket`: el estado HTTP y el cuerpo JSON (`{}` si no vino).
typedef RespuestaDeLaFuncion = ({int status, Map<String, Object?> cuerpo});

/// [ServidorDeFotosDeTicket] sobre la Edge Function `foto-ticket` de Supabase y el `PUT` al enlace
/// firmado de Cloudflare R2 (backend-supabase#182; HU-COB-007).
///
/// 1. Pide el enlace con `{accion: 'subir', ticketId, tipoDeImagen, bytes}` y la sesión del colportor
///    (la función comprueba en la base que el ticket sea suyo; la carpeta de la ruta sale de la sesión).
/// 2. Hace `PUT <url>` con el cuerpo de la foto y **exactamente** las `cabeceras` que devolvió la
///    función (la firma las ata; con otro tipo o largo, R2 contesta 403). Sin otras cabeceras.
/// 3. La `ruta` que devolvió la función es lo que va en `ticket.url_cloud`.
///
/// Todo fallo es un [SubidaFallida], nunca una excepción. Reintentables (después sale): sin red, sin
/// sesión (`401`), ticket que todavía no llegó al servidor (`404 ticket_no_encontrado`: el motor aún no
/// subió la fila), R2 o la función caídos (`5xx`), enlace vencido (`403` del `PUT`). No reintentables:
/// foto de más de 2 MiB (`413`), tipo que no acepta (`415`), pedido mal formado (`400`), foto vencida
/// a los 4 meses (`410`). `409 foto_ya_subida` es [FotoYaEstaba]: se toma como «la foto ya está».
///
/// El enlace firmado es del portador: no se loguea ni se guarda. El log lleva solo el id del ticket y
/// un código.
final class ServidorDeFotosSupabase implements ServidorDeFotosDeTicket {
  /// [_pedirEnlace] y [_ponerFoto] son las costuras de los tests.
  ServidorDeFotosSupabase(
    this._pedirEnlace,
    this._ponerFoto,
    this._usuarioActual, {
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  /// Sobre el cliente de Supabase y `http` de la app.
  factory ServidorDeFotosSupabase.conCliente(SupabaseClient cliente, {http.Client? clienteWeb}) {
    final web = clienteWeb ?? http.Client();
    return ServidorDeFotosSupabase(
      (cuerpo) async {
        try {
          final r = await cliente.functions.invoke('foto-ticket', body: cuerpo);
          return (status: r.status, cuerpo: _comoMapa(r.data));
        } on FunctionException catch (e) {
          return (status: e.status, cuerpo: _comoMapa(e.details));
        }
      },
      (url, cabeceras, bytes) async {
        final pedido = _putFirmado(url, cabeceras, bytes);
        final respuesta = await web.send(pedido);
        await respuesta.stream.drain<void>();
        return respuesta.statusCode;
      },
      () => cliente.auth.currentUser?.id,
    );
  }

  final Future<RespuestaDeLaFuncion> Function(Map<String, Object?> cuerpo) _pedirEnlace;
  final Future<int> Function(Uri url, Map<String, String> cabeceras, Uint8List bytes) _ponerFoto;
  final String? Function() _usuarioActual;
  final AppLogger _log;

  @override
  Future<ResultadoDeSubidaDeFoto> subir({
    required String ticketId,
    required TipoDeImagen tipo,
    required Uint8List bytes,
  }) async {
    try {
      final enlace = await _pedirEnlace({
        'accion': 'subir',
        'ticketId': ticketId,
        'tipoDeImagen': tipo.mime,
        'bytes': bytes.length,
      });
      switch (enlace.status) {
        case 200:
          break;
        case 409:
          final usuario = _usuarioActual();
          if (usuario == null) return _fallo(ticketId, 'sin_sesion', reintentable: true);
          return FotoYaEstaba('$usuario/$ticketId.${tipo.extension}');
        default:
          return _falloDeLaFuncion(ticketId, enlace.status);
      }

      final url = enlace.cuerpo['url'];
      final ruta = enlace.cuerpo['ruta'];
      final cabeceras = enlace.cuerpo['cabeceras'];
      if (url is! String || ruta is! String || cabeceras is! Map) {
        return _fallo(ticketId, 'respuesta_invalida', reintentable: true);
      }
      final status = await _ponerFoto(Uri.parse(url), {
        for (final e in cabeceras.entries) '${e.key}': '${e.value}',
      }, bytes);
      if (status >= 200 && status < 300) return FotoSubida(ruta);
      // 403: el enlace venció o la firma no coincide; se pide uno nuevo en la próxima pasada.
      return _fallo(ticketId, 'put_$status', reintentable: true);
    } on Object catch (e) {
      if (_esFallaDeRed(e)) return _fallo(ticketId, 'red', reintentable: true);
      if (e is AuthException) return _fallo(ticketId, 'sin_sesion', reintentable: true);
      return _fallo(ticketId, 'inesperado', reintentable: true);
    }
  }

  SubidaFallida _falloDeLaFuncion(String ticketId, int status) => switch (status) {
    401 => _fallo(ticketId, 'sin_sesion', reintentable: true),
    // El ticket todavía no está en el servidor (el motor no subió la fila) o no es de esta sesión.
    404 => _fallo(ticketId, 'ticket_no_encontrado', reintentable: true),
    400 => _fallo(ticketId, 'pedido_invalido', reintentable: false),
    410 => _fallo(ticketId, 'foto_vencida', reintentable: false),
    413 => _fallo(ticketId, 'foto_muy_pesada', reintentable: false),
    415 => _fallo(ticketId, 'tipo_no_aceptado', reintentable: false),
    _ => _fallo(ticketId, 'servidor_$status', reintentable: true),
  };

  SubidaFallida _fallo(String ticketId, String codigo, {required bool reintentable}) {
    _log.warn(LogModulo.net, 'TICKET_FOTO_SUBIDA_FAIL', 'no se pudo subir la foto de un ticket', {
      'ticket_id': ticketId,
      'codigo': codigo,
    });
    return SubidaFallida(codigo: codigo, reintentable: reintentable);
  }

  static Map<String, Object?> _comoMapa(Object? datos) => datos is Map
      ? {for (final e in datos.entries) '${e.key}': e.value}
      : const <String, Object?>{};

  static bool _esFallaDeRed(Object e) =>
      e is IOException || e is http.ClientException || e is TimeoutException;
}

/// El `PUT` al enlace firmado, con las cabeceras exactas de la función y nada más.
http.BaseRequest _putFirmado(Uri url, Map<String, String> cabeceras, Uint8List bytes) {
  final pedido = http.Request('PUT', url)..bodyBytes = bytes;
  pedido.headers
    ..clear()
    ..addAll(cabeceras);
  return pedido;
}
