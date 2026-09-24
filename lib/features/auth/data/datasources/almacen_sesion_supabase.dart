import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/politica_sesion.dart';
import 'emision_jwt.dart';

/// Dónde guarda `supabase_flutter` la sesión (JWT de acceso + refresh token): el almacén seguro
/// del equipo (Keystore/Keychain), no SharedPreferences, que es su default (§8.2, HU-AUTH-003 y
/// HU-AUTH-007: "el cliente guarda el nuevo `access_token` en `secure_storage`"). Cada refresh
/// del proveedor pasa por [persistSession] y reemplaza la anterior.
///
/// Es también la puerta de la sesión deslizante (HU-AUTH-007): si la sesión guardada lleva más
/// de 30 días sin que el servidor la renueve ([PoliticaSesion]), no se la entrega al proveedor
/// —que la refrescaría y la reviviría— sino que la descarta y lo avisa ([vencimientos],
/// [tomarVencimiento]). Pasa al arrancar (`Supabase.initialize`) y al volver a la app.
///
/// El usuario no puede hacer nada con una falla del almacén acá: todo va al log y la operación
/// sigue. Una lectura que falla no borra nada (se reintenta en el próximo arranque).
final class AlmacenSesionSupabase implements LocalStorage {
  AlmacenSesionSupabase(
    this._almacen, {
    this._anterior,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;

  /// Donde la guardaba antes (SharedPreferences): se migra una vez y se borra de ahí.
  final LocalStorage? _anterior;
  final DateTime Function() _ahora;
  final AppLogger _log;

  final _vencimientos = StreamController<void>.broadcast();
  bool _vencioSinAvisar = false;

  /// Emite cada vez que se descarta una sesión por inactividad.
  Stream<void> get vencimientos => _vencimientos.stream;

  /// `true` una sola vez después de descartar una sesión por inactividad: al arrancar pasa antes
  /// de que alguien escuche [vencimientos].
  bool tomarVencimiento() {
    final vencio = _vencioSinAvisar;
    _vencioSinAvisar = false;
    return vencio;
  }

  @override
  Future<void> initialize() async {
    final anterior = _anterior;
    if (anterior == null) return;
    try {
      await anterior.initialize();
      if (!await anterior.hasAccessToken()) return;
      final vieja = await anterior.accessToken();
      if (vieja != null && await _almacen.leer(ClaveSegura.sesionAuth) == null) {
        await _almacen.escribir(ClaveSegura.sesionAuth, vieja);
      }
      // Recién con la copia a salvo: si escribir falló, la vieja queda para el próximo arranque.
      await anterior.removePersistedSession();
      _log.info(LogModulo.auth, 'SESION_MIGRADA', 'sesión movida al almacén seguro');
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'SESION_MIGRAR_FAIL',
        'no se pudo migrar la sesión',
        const {},
        e,
        st,
      );
    }
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;

  @override
  Future<String?> accessToken() async {
    final String? guardada;
    try {
      guardada = await _almacen.leer(ClaveSegura.sesionAuth);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'SESION_LEER_FAIL', 'no se pudo leer la sesión', const {}, e, st);
      return null;
    }
    if (guardada == null) return null;

    final emitida = _emision(guardada);
    if (emitida == null) {
      _log.warn(LogModulo.auth, 'SESION_ILEGIBLE', 'sesión guardada ilegible: se descarta');
      await _borrar();
      return null;
    }
    if (PoliticaSesion.vencida(PoliticaSesion.expiraEn(emitida), _ahora())) {
      _log.info(LogModulo.auth, 'SESION_VENCIDA_INACTIVIDAD', 'sesión sin uso por 30 días', {
        'emitida': emitida.toIso8601String(),
      });
      await _borrar();
      _vencioSinAvisar = true;
      _vencimientos.add(null);
      return null;
    }
    return guardada;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _almacen.escribir(ClaveSegura.sesionAuth, persistSessionString);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'SESION_GUARDAR_FAIL',
        'no se pudo guardar la sesión',
        const {},
        e,
        st,
      );
    }
  }

  @override
  Future<void> removePersistedSession() => _borrar();

  Future<void> _borrar() async {
    try {
      await _almacen.borrar(ClaveSegura.sesionAuth);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'SESION_BORRAR_FAIL',
        'no se pudo borrar la sesión',
        const {},
        e,
        st,
      );
    }
  }

  /// Cuándo emitió el servidor la sesión guardada (el `iat` de su JWT), o `null` si está rota.
  /// El `FormatException` de `jsonDecode` no se loguea: su texto lleva el token.
  static DateTime? _emision(String guardada) {
    try {
      final sesion = jsonDecode(guardada);
      final token = sesion is Map<String, Object?> ? sesion['access_token'] : null;
      return token is String ? emisionDelJwt(token) : null;
    } on FormatException {
      return null;
    }
  }
}
