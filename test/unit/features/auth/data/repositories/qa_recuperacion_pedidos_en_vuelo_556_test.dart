// QA de #556 (29/10), P2: pedidos de cambio de contraseña superpuestos en el repositorio.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/recuperacion_password_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/recuperacion_password_repository_impl.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Un remoto que solo sabe cambiar la contraseña y cuenta cuántos pedidos hay en el aire a la vez.
class _RemotoQueMideSolapes implements RecuperacionPasswordRemoteDataSource {
  final Completer<void> primeraVarada = Completer<void>();
  final List<String> enOrden = [];
  int enElAire = 0;
  int maximoEnElAire = 0;
  bool _primera = true;

  @override
  Future<void> actualizarPassword(String nueva) async {
    enElAire++;
    if (enElAire > maximoEnElAire) maximoEnElAire = enElAire;
    try {
      if (_primera) {
        _primera = false;
        await primeraVarada.future;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      enOrden.add(nueva);
    } finally {
      enElAire--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'dado A varada pasado el tope, cuando B y C llegan a la vez, nunca hay dos pedidos en el '
    'aire (cada uno espera al anterior)',
    () async {
      final remoto = _RemotoQueMideSolapes();
      final repo = RecuperacionPasswordRepositoryImpl(
        remoto,
        logger: loggerMudo(),
        tope: const Duration(milliseconds: 50),
      );

      expect(await repo.actualizarPassword('ClaveAaaa1'), isA<Left<Failure, Unit>>());
      final b = repo.actualizarPassword('ClaveBbbb1');
      final c = repo.actualizarPassword('ClaveCccc1');
      remoto.primeraVarada.complete();
      await Future.wait([b, c]);

      expect(remoto.maximoEnElAire, 1, reason: 'B y C salieron juntos tras esperar a A');
      expect(remoto.enOrden, ['ClaveAaaa1', 'ClaveBbbb1', 'ClaveCccc1']);
    },
    skip:
        'QA #556: dos guardados que esperan al mismo pedido varado salen juntos (menor: la '
        'pantalla bloquea el botón mientras guarda, solo se da llamando al repositorio dos veces)',
  );
}
