import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/politica_sesion.dart';
import '../../domain/services/reloj_sesion.dart';
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
/// La ventana se mide con [RelojSesion], que no vuelve atrás aunque se atrase el reloj del equipo.
///
/// El usuario no puede hacer nada con una falla del almacén acá: todo va al log y la operación
/// sigue. Una lectura que falla no borra nada (se reintenta en el próximo arranque).
final class AlmacenSesionSupabase implements LocalStorage {
  AlmacenSesionSupabase(this._almacen, this._reloj, {this._anterior, AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final RelojSesion _reloj;

  /// Donde la guardaba antes (SharedPreferences): se migra una vez y se borra de ahí.
  final LocalStorage? _anterior;
  final AppLogger _log;

  /// La sesión vieja que no se pudo escribir en el almacén al migrar: se sirve igual en esta
  /// corrida (el usuario no queda afuera) y se reintenta la migración en el próximo arranque.
  String? _migradaSoloEnMemoria;

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
      final yaMigrada = await _almacen.leer(ClaveSegura.sesionMigrada) != null;
      final vieja = await anterior.hasAccessToken() ? await anterior.accessToken() : null;
      if (vieja != null && !yaMigrada && await _almacen.leer(ClaveSegura.sesionAuth) == null) {
        try {
          await _almacen.escribir(ClaveSegura.sesionAuth, vieja);
        } on Object catch (e, st) {
          // La vieja queda en SharedPreferences para reintentar; en esta corrida se sirve igual.
          _migradaSoloEnMemoria = vieja;
          _log.error(
            LogModulo.auth,
            'SESION_MIGRAR_FAIL',
            'no se pudo escribir la sesión en el almacén: se usa en memoria',
            const {},
            e,
            st,
          );
          return;
        }
      }
      // Ya migrada (o sin nada que migrar): una copia que quedó en SharedPreferences, por ejemplo
      // después de un logout, no se vuelve a usar; solo se limpia.
      if (vieja != null) await anterior.removePersistedSession();
      if (!yaMigrada) await _almacen.escribir(ClaveSegura.sesionMigrada, '1');
      if (vieja != null && !yaMigrada) {
        _log.info(LogModulo.auth, 'SESION_MIGRADA', 'sesión movida al almacén seguro');
      }
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
    String? guardada;
    try {
      guardada = await _almacen.leer(ClaveSegura.sesionAuth);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'SESION_LEER_FAIL', 'no se pudo leer la sesión', const {}, e, st);
      return null;
    }
    guardada ??= _migradaSoloEnMemoria;
    if (guardada == null) return null;

    final emitida = _emision(guardada);
    if (emitida == null) {
      _log.warn(LogModulo.auth, 'SESION_ILEGIBLE', 'sesión guardada ilegible: se descarta');
      await _borrar();
      return null;
    }
    if (PoliticaSesion.vencida(PoliticaSesion.expiraEn(emitida), await _reloj.ahora())) {
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
    // El `iat` de la sesión nueva es la hora del servidor: el reloj de la sesión no puede quedar
    // antes de eso.
    final emitida = _emision(persistSessionString);
    if (emitida != null) await _reloj.registrar(emitida);
    try {
      await _almacen.escribir(ClaveSegura.sesionAuth, persistSessionString);
      _migradaSoloEnMemoria = null;
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
    _migradaSoloEnMemoria = null;
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
  /// La excepción de `jsonDecode` no se loguea: su texto lleva el token.
  static DateTime? _emision(String guardada) {
    try {
      final sesion = jsonDecode(guardada);
      final token = sesion is Map<String, Object?> ? sesion['access_token'] : null;
      return token is String ? emisionDelJwt(token) : null;
    } on Object {
      return null;
    }
  }
}
