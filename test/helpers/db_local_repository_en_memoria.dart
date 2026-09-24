// Dispositivo simulado para los tests de dominio de HU-AUTH-009 (ADR-006): marca, archivo, DEK en el
// almacén y envoltorio por contraseña, más el registro de qué se pidió y en qué orden. Dart puro.
//
// Imita el orden de escrituras y las fallas del repositorio real (`DbLocalRepositoryImpl` sobre
// `CustodiaClaveDb` y `DatabaseHelper`), no solo el resultado: la reconstrucción del almacén no es
// atómica y se puede cortar en cada escritura, y los `StateError` de la infraestructura llegan como
// `FailureInesperado` (revisión del PR #81).
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/db_local_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/vigencia_sesion.dart';
import 'package:dartz/dartz.dart';

bool _mismosBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final class DbLocalRepositoryEnMemoria implements DbLocalRepository {
  MarcaDbLocal marca = MarcaDbLocal.ausente;
  bool archivo = false;
  bool abierta = false;
  bool bloqueoPantalla = true;
  bool consentimiento = false;
  NivelAlmacenSeguro nivel = NivelAlmacenSeguro.hardware;

  /// Con qué DEK está cifrado el archivo. `null` con [archivo] en `true` = cualquiera lo abre (los
  /// tests que no miran eso).
  Uint8List? claveDelArchivo;

  /// Bytes de la DEK del almacén, o `null` si no hay.
  Uint8List? dekEnAlmacen;

  /// Bytes de la DEK envuelta y la contraseña con que se envolvió, o `null` si no hay envoltorio.
  ({Uint8List dek, String password})? envoltorio;

  final llamadas = <String>[];

  /// Las DEK entregadas (creadas, leídas o desenvueltas), en orden.
  final entregadas = <ClaveDb>[];

  /// La DEK con la que se abrió la DB, si se abrió.
  ClaveDb? abiertaCon;

  /// Falla a devolver por operación: `estado`, `bloqueo`, `nivel`, `consentimiento`, `leerDek`,
  /// `crearDek`, `envolver`, `desenvolver`, `abrir`, `marcar`, `descartar`. La reconstrucción del
  /// almacén se corta con [reconstruccionSeCortaEn].
  final fallas = <String, Failure>{};

  /// Escritura de la reconstrucción del almacén en la que el Keystore falla: 1 = la primera (la
  /// marca), 2 = la segunda (la DEK). Lo anterior ya quedó escrito, como en el almacén real.
  int? reconstruccionSeCortaEn;

  /// Si está, [envolverConPassword] y [desenvolverConPassword] (el Argon2id) esperan a que el test
  /// la complete.
  Completer<void>? argon2idPendiente;

  /// Se completa cuando alguien empieza el Argon2id (envolver o desenvolver).
  final pidioArgon2id = Completer<void>();

  /// Si está, [leerDek] espera a que el test la complete.
  Completer<void>? lecturaPendiente;

  int _creadas = 0;

  Either<Failure, T> _o<T>(String op, T Function() valor) {
    llamadas.add(op);
    final falla = fallas[op];
    return falla != null ? Left(falla) : Right(valor());
  }

  ClaveDb _entregar(Uint8List bytes) {
    final dek = ClaveDb(Uint8List.fromList(bytes));
    entregadas.add(dek);
    return dek;
  }

  @override
  Future<Either<Failure, EstadoDbLocal>> estado() async => _o(
    'estado',
    () => EstadoDbLocal(
      marca: marca,
      archivoExiste: archivo,
      envoltorioExiste: envoltorio != null,
      abierta: abierta,
    ),
  );

  @override
  Future<Either<Failure, bool>> tieneBloqueoPantalla() async =>
      _o('bloqueo', () => bloqueoPantalla);

  @override
  Future<Either<Failure, NivelAlmacenSeguro>> nivelAlmacenSeguro() async =>
      _o('nivel', () => nivel);

  @override
  Future<Either<Failure, Unit>> registrarConsentimientoAlmacenSoftware() async =>
      _o('consentimiento', () {
        consentimiento = true;
        return unit;
      });

  @override
  Future<Either<Failure, ClaveDb?>> leerDek() async {
    await lecturaPendiente?.future;
    return _o('leerDek', () {
      final bytes = dekEnAlmacen;
      return bytes == null ? null : _entregar(bytes);
    });
  }

  @override
  Future<Either<Failure, ClaveDb>> crearDek() async {
    final r = _o('crearDek', () => unit);
    if (r case Left(value: final falla)) return Left(falla);
    // `CustodiaClaveDb.guardarDek` lanza StateError con la marca puesta; el repositorio lo
    // devuelve como FailureInesperado.
    if (marca == MarcaDbLocal.puesta) return const Left(FailureInesperado());
    final bytes = Uint8List.fromList(List<int>.filled(32, ++_creadas));
    dekEnAlmacen = bytes;
    return Right(_entregar(bytes));
  }

  @override
  Future<Either<Failure, Unit>> envolverConPassword(ClaveDb dek, String password) async {
    final bytes = Uint8List.fromList(dek.bytes);
    await _argon2id();
    return _o('envolver', () {
      envoltorio = (dek: bytes, password: password);
      return unit;
    });
  }

  @override
  Future<Either<Failure, ClaveDb>> desenvolverConPassword(String password) async {
    await _argon2id();
    llamadas.add('desenvolver');
    final falla = fallas['desenvolver'];
    if (falla != null) return Left(falla);
    final guardado = envoltorio;
    if (guardado == null) return const Left(FailureAlmacenSeguroSinRecuperacion());
    if (guardado.password != password) return const Left(FailurePasswordNoAbreDatos());
    return Right(_entregar(guardado.dek));
  }

  Future<void> _argon2id() async {
    if (!pidioArgon2id.isCompleted) pidioArgon2id.complete();
    await argon2idPendiente?.future;
  }

  /// Como `CustodiaClaveDb.reconstruirAlmacen`: `borrarTodo` → marca → DEK → consentimiento, una
  /// escritura por vez.
  @override
  Future<Either<Failure, Unit>> reconstruirAlmacen(ClaveDb dek) async {
    llamadas.add('reconstruir');
    final conservaConsentimiento = consentimiento;
    marca = MarcaDbLocal.ausente;
    dekEnAlmacen = null;
    consentimiento = false;
    if (reconstruccionSeCortaEn == 1) return const Left(FailureAlmacenSeguro());
    marca = MarcaDbLocal.puesta;
    if (reconstruccionSeCortaEn == 2) return const Left(FailureAlmacenSeguro());
    dekEnAlmacen = Uint8List.fromList(dek.bytes);
    consentimiento = conservaConsentimiento;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> abrir(ClaveDb dek) async {
    final r = _o('abrir', () => unit);
    if (r.isLeft()) {
      dek.destruir();
      return r;
    }
    // `DatabaseHelper.abrir` lanza StateError si ya hay una abierta: llega como FailureInesperado.
    if (abierta) {
      dek.destruir();
      return const Left(FailureInesperado());
    }
    final clave = claveDelArchivo;
    if (archivo && clave != null && !_mismosBytes(clave, dek.bytes)) {
      dek.destruir();
      return const Left(FailureClaveDbIncorrecta());
    }
    if (!archivo) claveDelArchivo = Uint8List.fromList(dek.bytes);
    abierta = true;
    archivo = true;
    abiertaCon = dek;
    return r;
  }

  @override
  Future<Either<Failure, Unit>> marcarInicializada() async => _o('marcar', () {
    marca = MarcaDbLocal.puesta;
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> descartar() async => _o('descartar', () {
    abierta = false;
    archivo = false;
    claveDelArchivo = null;
    marca = MarcaDbLocal.ausente;
    dekEnAlmacen = null;
    envoltorio = null;
    consentimiento = false;
    return unit;
  });
}

/// Testigo que el test puede invalidar a mano.
final class TestigoManual implements TestigoSesion {
  bool vigente = true;

  @override
  bool get sigueVigente => vigente;
}

/// Sesión simulada: [cerrarSesion] invalida el testigo que ya se entregó.
final class VigenciaEnMemoria implements VigenciaSesion {
  bool haySesion = true;
  final testigo = TestigoManual();

  void cerrarSesion() {
    haySesion = false;
    testigo.vigente = false;
  }

  @override
  TestigoSesion? tomarTestigo() => haySesion ? testigo : null;
}
