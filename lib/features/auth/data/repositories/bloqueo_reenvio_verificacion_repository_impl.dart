import 'dart:convert';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/reenvios_guardados.dart';
import '../../domain/repositories/bloqueo_reenvio_verificacion_repository.dart';

/// [BloqueoReenvioVerificacionRepository] sobre el almacén seguro
/// (`ClaveSegura.bloqueoReenvioVerificacion`): un JSON
/// `{"<correo>": {"bloqueo": "<vencimiento ISO 8601 UTC>", "espera": "<ídem>"}}` (cada campo
/// opcional) que solo guarda lo vigente. Cada lectura y cada guardado podan lo vencido y recortan
/// lo que pasa de su tope, y la clave se borra cuando no queda nada: ningún correo sigue en el
/// teléfono pasada su hora (decisión del orquestador, 08/10, #325).
///
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de un
/// guardado en vuelo ve el bloqueo nuevo, y dos guardados seguidos no se pisan (cada uno lee lo
/// que dejó el anterior).
///
/// Un valor que no se puede interpretar (JSON roto, fecha rota) cuenta como «nada guardado»: se
/// pisa con lo nuevo. **Pero si el almacén no se deja leer no se escribe nada**: pisaría lo que hay
/// de las otras direcciones (el candado es una comodidad de la pantalla; el límite de verdad lo
/// aplica el servidor). Sin el correo en los logs.
final class BloqueoReenvioVerificacionRepositoryImpl
    implements BloqueoReenvioVerificacionRepository {
  BloqueoReenvioVerificacionRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  /// Lo guardado, sin los pares que no se pueden leer. Lanza si el almacén no se deja leer.
  Future<({bool habiaValor, ReenviosGuardados guardados})> _leerGuardados() async {
    final valor = await _almacen.leer(ClaveSegura.bloqueoReenvioVerificacion);
    return (habiaValor: valor != null, guardados: _interpretar(valor));
  }

  static ReenviosGuardados _interpretar(String? valor) {
    if (valor == null) return ReenviosGuardados.vacio;
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return ReenviosGuardados.vacio;
    }
    if (json is! Map<String, dynamic>) return ReenviosGuardados.vacio;
    final bloqueos = <String, DateTime>{};
    final esperas = <String, DateTime>{};
    for (final MapEntry(key: correo, value: guardado) in json.entries) {
      if (correo.isEmpty) continue;
      switch (guardado) {
        case final String vence:
          // La forma de #249: solo el candado.
          _agregar(bloqueos, correo, vence);
        case final Map<String, dynamic> campos:
          _agregar(bloqueos, correo, campos['bloqueo']);
          _agregar(esperas, correo, campos['espera']);
        case _:
          break;
      }
    }
    return ReenviosGuardados(bloqueos: bloqueos, esperas: esperas);
  }

  static void _agregar(Map<String, DateTime> destino, String correo, Object? vence) {
    if (vence is! String) return;
    final instante = DateTime.tryParse(vence.trim());
    if (instante != null) destino[correo] = instante.toUtc();
  }

  static String _codificar(ReenviosGuardados guardados) {
    final correos = {...guardados.bloqueos.keys, ...guardados.esperas.keys};
    return jsonEncode({
      for (final correo in correos)
        correo: {
          if (guardados.bloqueos[correo] case final bloqueo?) 'bloqueo': bloqueo.toIso8601String(),
          if (guardados.esperas[correo] case final espera?) 'espera': espera.toIso8601String(),
        },
    });
  }

  /// Deja en el almacén [guardados]; con nada vigente, borra la clave.
  Future<void> _persistir(ReenviosGuardados guardados) => guardados.estaVacio
      ? _almacen.borrar(ClaveSegura.bloqueoReenvioVerificacion)
      : _almacen.escribir(ClaveSegura.bloqueoReenvioVerificacion, _codificar(guardados));

  @override
  Future<ReenviosGuardados> leer({required DateTime ahora}) => _encolar(() async {
    final ({bool habiaValor, ReenviosGuardados guardados}) leido;
    try {
      leido = await _leerGuardados();
    } on Object catch (e) {
      _avisar('VERIFICACION_BLOQUEO_LEER', 'no se pudo leer el reenvío de verificación', e);
      return ReenviosGuardados.vacio;
    }
    final vigentes = leido.guardados.vigentesA(ahora);
    // Poda y recorte quedan en el teléfono: nada vencido se queda guardado, y un vencimiento muy
    // lejano no se corre una hora más en cada apertura. Con nada vigente, la clave se va.
    final cambio = vigentes != leido.guardados || (vigentes.estaVacio && leido.habiaValor);
    if (cambio) {
      try {
        await _persistir(vigentes);
      } on Object catch (e) {
        _avisar('VERIFICACION_BLOQUEO_PODAR', 'no se pudo podar el reenvío de verificación', e);
      }
    }
    return vigentes;
  });

  /// Lee lo guardado, aplica [cambio] y lo deja guardado. Con [ahora], antes poda lo que venció a
  /// esa hora. Si el almacén no se deja leer, no escribe.
  Future<void> _actualizar(
    String codigo,
    String mensaje,
    ReenviosGuardados Function(ReenviosGuardados actual) cambio, {
    DateTime? ahora,
  }) => _encolar(() async {
    try {
      final actual = (await _leerGuardados()).guardados;
      await _persistir(cambio(ahora == null ? actual : actual.vigentesA(ahora)));
    } on Object catch (e) {
      _avisar(codigo, mensaje, e);
    }
  });

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) => _actualizar(
    'VERIFICACION_BLOQUEO_ESCRIBIR',
    'no se pudo guardar el bloqueo del reenvío de verificación',
    (actual) => actual.conBloqueo(correo, vence),
    ahora: ahora,
  );

  @override
  Future<void> guardarEspera(String correo, DateTime vence, {required DateTime ahora}) =>
      _actualizar(
        'VERIFICACION_ESPERA_ESCRIBIR',
        'no se pudo guardar la espera del reenvío de verificación',
        (actual) => actual.conEspera(correo, vence),
        ahora: ahora,
      );

  @override
  Future<void> olvidar(String correo) => _actualizar(
    'VERIFICACION_BLOQUEO_OLVIDAR',
    'no se pudo olvidar el reenvío de verificación de una dirección',
    (actual) => actual.sin(correo),
  );

  @override
  Future<void> olvidarTodo() => _encolar(() async {
    try {
      await _almacen.borrar(ClaveSegura.bloqueoReenvioVerificacion);
    } on Object catch (e) {
      _avisar(
        'VERIFICACION_BLOQUEO_BORRAR',
        'no se pudo borrar el reenvío de verificación guardado',
        e,
      );
    }
  });

  void _avisar(String codigo, String mensaje, Object error) =>
      _log.warn(LogModulo.auth, codigo, mensaje, {'error': error.runtimeType.toString()});
}

/// [BloqueoReenvioVerificacionRepository] en memoria: el default de los tests y de la app sin
/// Keystore. **No es código de producción**: `main.dart` lo reemplaza por
/// [BloqueoReenvioVerificacionRepositoryImpl].
final class BloqueoReenvioVerificacionEnMemoria implements BloqueoReenvioVerificacionRepository {
  /// Con [bloqueos] ya guardados (correo normalizado → vencimiento del candado).
  BloqueoReenvioVerificacionEnMemoria([Map<String, DateTime> bloqueos = const {}])
    : this.con(bloqueos: bloqueos);

  /// Con [bloqueos] y [esperas] ya guardados (correo normalizado → vencimiento).
  BloqueoReenvioVerificacionEnMemoria.con({
    Map<String, DateTime> bloqueos = const {},
    Map<String, DateTime> esperas = const {},
  }) : _guardados = ReenviosGuardados(
         bloqueos: {for (final MapEntry(:key, :value) in bloqueos.entries) key: value.toUtc()},
         esperas: {for (final MapEntry(:key, :value) in esperas.entries) key: value.toUtc()},
       );

  ReenviosGuardados _guardados;

  @override
  Future<ReenviosGuardados> leer({required DateTime ahora}) async =>
      _guardados = _guardados.vigentesA(ahora);

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) async {
    _guardados = _guardados.vigentesA(ahora).conBloqueo(correo, vence);
  }

  @override
  Future<void> guardarEspera(String correo, DateTime vence, {required DateTime ahora}) async {
    _guardados = _guardados.vigentesA(ahora).conEspera(correo, vence);
  }

  @override
  Future<void> olvidar(String correo) async {
    _guardados = _guardados.sin(correo);
  }

  @override
  Future<void> olvidarTodo() async {
    _guardados = ReenviosGuardados.vacio;
  }
}
