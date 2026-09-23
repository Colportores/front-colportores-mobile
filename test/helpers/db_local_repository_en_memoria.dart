// Dispositivo simulado para los tests de dominio de HU-AUTH-009 (ADR-006): marca, archivo, DEK en el
// almacén y envoltorio por contraseña, más el registro de qué se pidió y en qué orden. Dart puro.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/db_local_repository.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/vigencia_sesion.dart';
import 'package:dartz/dartz.dart';

final class DbLocalRepositoryEnMemoria implements DbLocalRepository {
  MarcaDbLocal marca = MarcaDbLocal.ausente;
  bool archivo = false;
  bool abierta = false;
  bool bloqueoPantalla = true;
  bool consentimiento = false;
  NivelAlmacenSeguro nivel = NivelAlmacenSeguro.hardware;

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
  /// `crearDek`, `envolver`, `desenvolver`, `reconstruir`, `abrir`, `marcar`, `descartar`.
  final fallas = <String, Failure>{};

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
    () => EstadoDbLocal(marca: marca, archivoExiste: archivo, envoltorioExiste: envoltorio != null),
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
  Future<Either<Failure, ClaveDb>> crearDek() async => _o('crearDek', () {
    final bytes = Uint8List.fromList(List<int>.filled(32, ++_creadas));
    dekEnAlmacen = bytes;
    return _entregar(bytes);
  });

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

  @override
  Future<Either<Failure, Unit>> reconstruirAlmacen(ClaveDb dek) async => _o('reconstruir', () {
    dekEnAlmacen = Uint8List.fromList(dek.bytes);
    marca = MarcaDbLocal.puesta;
    consentimiento = false;
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> abrir(ClaveDb dek) async {
    final r = _o('abrir', () => unit);
    if (r.isLeft()) {
      dek.destruir();
    } else {
      abierta = true;
      archivo = true;
      abiertaCon = dek;
    }
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
