// Test de la capa data: Dart puro, con los data sources en memoria.
//
// Complementa `auth_repository_impl_test.dart` (compartido con otro QA en paralelo — no se toca
// ese archivo) con el escenario explícito del issue #16: "red caída a mitad de registro", es
// decir, ¿qué pasa si falla *después* de que Supabase Auth ya creó la cuenta y *antes* de que se
// persista algo localmente? `AuthRepositoryImpl.registrar` solo persiste la sesión localmente
// (`_local.guardarSesion`) — el perfil (nombre/apellido/cédula) todavía no se persiste en ningún
// lado, a propósito, hasta que la DB cifrada exista (#6, ver el doc-comment de `Usuario`).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_registro.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Local que ya tiene una sesión guardada, pero revienta con una excepción genérica en
/// `guardarSesion` — simula que el dispositivo se quedó sin red/almacenamiento justo después de
/// que Supabase ya confirmó la cuenta (la llamada remota ya volvió con éxito).
final class _LocalQueFallaAlGuardar implements AuthLocalDataSource {
  int llamadas = 0;

  @override
  Future<SesionModel?> leerSesion() async => null;

  @override
  Future<void> guardarSesion(SesionModel sesion) async {
    llamadas++;
    throw Exception('conexión perdida justo al persistir');
  }

  @override
  Future<void> borrarSesion() async {}
}

void main() {
  group('AuthRepositoryImpl.registrar — red caída a mitad de registro', () {
    test('cuando la cuenta ya se creó en el remoto pero falla la persistencia local, devuelve '
        'FailureInesperado sin perder la cuenta ya creada del lado remoto', () async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      final localRoto = _LocalQueFallaAlGuardar();
      final repository = AuthRepositoryImpl(remote, localRoto, logger: loggerMudo());

      final resultado = await repository.registrar(
        nombre: 'Bruno',
        apellido: 'Díaz',
        cedula: '12345678',
        email: 'bruno@example.com',
        password: 'Secreto123',
      );

      // La UI ve un error genérico...
      expect(resultado.isLeft(), isTrue);
      final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
      expect(failure, isA<FailureInesperado>());
      expect(localRoto.llamadas, 1);

      // ...pero la cuenta remota ya existe: Supabase Auth no se revierte. Un reintento del
      // mismo registro tiene que toparse con "email ya registrado", no repetir el alta.
      expect(remote.usuariosRegistrados.containsKey('bruno@example.com'), isTrue);
      final reintento = await repository.registrar(
        nombre: 'Bruno',
        apellido: 'Díaz',
        cedula: '12345678',
        email: 'bruno@example.com',
        password: 'Secreto123',
      );
      expect(reintento, const Left<Failure, ResultadoRegistro>(FailureEmailYaRegistrado()));
    });
  });
}
