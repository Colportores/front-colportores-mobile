// Falsos del respaldo en Drive (HU-SYNC-004): Google, el primer respaldo y un repositorio armado
// sobre el almacén en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/respaldo/data/repositories/respaldo_drive_repository_impl.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/respaldo_drive_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'logger_mudo.dart';

/// La cuenta con la que prueban casi todos los tests.
const cuentaDeAna = CuentaGoogle(id: 'g-100', email: 'ana.gomez@gmail.com');

/// [ServicioGoogle] que hace lo que el test le diga.
final class ServicioGoogleFalso implements ServicioGoogle {
  ServicioGoogleFalso({this.cuenta = cuentaDeAna});

  /// La cuenta que elige la persona en la pantalla de Google.
  CuentaGoogle cuenta;

  /// Si no es `null`, [conectar] lo lanza (por ejemplo `GoogleSignInException(canceled)`).
  Object? errorAlConectar;

  /// Si no es `null`, [conectar] espera a que el test la complete (la persona está en la pantalla
  /// de Google).
  Completer<void>? compuertaConectar;

  /// El token que da [tokenSilencioso]; `null` = Google ya no tiene el permiso.
  String? token = 'ya29.token';

  /// Si no es `null`, [tokenSilencioso] lo lanza (sin red, Google caído).
  Object? errorAlPedirToken;

  /// Si no es `null`, [desconectar] lo lanza.
  Object? errorAlDesconectar;

  int conexiones = 0;
  int pedidosDeToken = 0;
  int desconexiones = 0;

  @override
  Future<CuentaGoogle> conectar() async {
    conexiones++;
    await compuertaConectar?.future;
    if (errorAlConectar case final e?) throw e;
    return cuenta;
  }

  @override
  Future<String?> tokenSilencioso() async {
    pedidosDeToken++;
    if (errorAlPedirToken case final e?) throw e;
    return token;
  }

  @override
  Future<void> desconectar() async {
    desconexiones++;
    if (errorAlDesconectar case final e?) throw e;
  }
}

/// [PrimerRespaldoDrive] que hace lo que el test le diga.
final class PrimerRespaldoFalso implements PrimerRespaldoDrive {
  bool resultado = true;
  Object? error;
  int llamadas = 0;

  @override
  Future<bool> hacer() async {
    llamadas++;
    if (error case final e?) throw e;
    return resultado;
  }
}

/// Un `GoogleSignInException` con el código pedido.
GoogleSignInException falloDeGoogle(GoogleSignInExceptionCode codigo) =>
    GoogleSignInException(code: codigo, description: 'prueba');

/// Almacén en memoria al que se le puede hacer fallar cada operación por separado.
final class AlmacenControlable implements AlmacenSeguro {
  final AlmacenSeguroEnMemoria _dentro = AlmacenSeguroEnMemoria();

  bool alLeer = false;

  /// Si no es `null`, [leer] espera a que el test la complete.
  Completer<void>? compuertaLeer;
  bool alEscribir = false;
  bool alBorrar = false;

  Map<ClaveSegura, String> get contenido => _dentro.contenido;

  @override
  Future<String?> leer(ClaveSegura clave) async {
    await compuertaLeer?.future;
    if (alLeer) throw AlmacenSeguroException(operacion: 'leer', clave: clave);
    return _dentro.leer(clave);
  }

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    if (alEscribir) throw AlmacenSeguroException(operacion: 'escribir', clave: clave);
    return _dentro.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    if (alBorrar) throw AlmacenSeguroException(operacion: 'borrar', clave: clave);
    return _dentro.borrar(clave);
  }

  @override
  Future<void> borrarTodo() => _dentro.borrarTodo();
}

/// El repositorio de verdad sobre un almacén en memoria y un Google falso.
final class RespaldoDriveArmado {
  RespaldoDriveArmado({PrimerRespaldoDrive? primerRespaldo})
    : google = ServicioGoogleFalso(),
      almacen = AlmacenControlable() {
    repo = RespaldoDriveRepositoryImpl(
      almacen,
      google,
      primerRespaldo: primerRespaldo ?? const PrimerRespaldoSinMotor(),
      logger: loggerMudo(),
    );
  }

  final ServicioGoogleFalso google;
  final AlmacenControlable almacen;
  late final RespaldoDriveRepositoryImpl repo;

  /// Lo guardado en el almacén seguro para el respaldo, o `null`.
  String? get guardado => almacen.contenido[ClaveSegura.respaldoDrive];
}
