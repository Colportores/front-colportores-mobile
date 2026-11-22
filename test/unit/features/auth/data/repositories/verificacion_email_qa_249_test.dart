// QA del PR #323 (#249, vista 12-A06): lo que el candado del reenvío de la verificación debe cumplir
// de punta a punta con el almacén y la custodia de la DEK de verdad, y la privacidad (§7.5 de
// convenciones-desarrollo.md: sin PII en logs ni en `toString()`).
import 'dart:io';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/bloqueo_reenvio_verificacion_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/bloqueo_reenvio_verificacion_use_cases.dart';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/proveedor_clave_db_falso.dart';

const _parametros = ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1);

/// Salida de logs en memoria, para ver qué se escribiría de verdad.
final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  final base = DateTime.utc(2026, 10, 8, 10);
  final venceEn1h = base.add(const Duration(hours: 1));
  const ana = 'ana@correo.com';

  group('el candado y la custodia de la DEK', () {
    late Directory dir;
    late AlmacenSeguroEnMemoria almacen;
    late CustodiaClaveDb custodia;
    late BloqueoReenvioVerificacionRepositoryImpl repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('qa249_');
      almacen = AlmacenSeguroEnMemoria();
      custodia = CustodiaClaveDb(
        almacen,
        ArchivoEnvoltorioDek(directorio: () async => dir),
        ProveedorClaveDbFalso(),
        CriptoSodium(),
        parametros: _parametros,
        logger: loggerMudo(),
      );
      repo = BloqueoReenvioVerificacionRepositoryImpl(almacen, logger: loggerMudo());
      await repo.guardar(ana, venceEn1h, ahora: base);
    });

    Future<Map<String, DateTime>> bloqueos() async => (await repo.leer(ahora: base)).bloqueos;

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('«Borrar datos locales» (olvidarDatosDelUsuario): ya no hay candados que leer', () async {
      expect(await bloqueos(), {ana: venceEn1h});

      await custodia.olvidarDatosDelUsuario();

      expect(await bloqueos(), isEmpty);
    });

    test('«Empezar de nuevo» (olvidar) y recuperar el almacén conservan el candado: Supabase sigue '
        'bloqueando a esa dirección', () async {
      await custodia.olvidar();
      expect(await bloqueos(), {ana: venceEn1h});

      await custodia.reconstruirAlmacen(custodia.generarDek());
      expect(await bloqueos(), {ana: venceEn1h});
    });

    test(
      'un candado guardado después de borrar los datos es del usuario nuevo y no se pierde',
      () async {
        await custodia.olvidarDatosDelUsuario();

        await repo.guardar('luis@correo.com', venceEn1h, ahora: base);

        expect(await bloqueos(), {'luis@correo.com': venceEn1h});
      },
    );
  });

  group('privacidad (§7.5)', () {
    test(
      'con el almacén roto, guardar y leer el candado no escriben la dirección en los logs',
      () async {
        final salida = _SalidaEnMemoria();
        final almacen = AlmacenSeguroEnMemoria()..simularFalla = true;
        final repo = BloqueoReenvioVerificacionRepositoryImpl(
          almacen,
          logger: AppLogger(output: salida),
        );

        await repo.guardar(ana, venceEn1h, ahora: base);
        await repo.guardarEspera(ana, base.add(const Duration(seconds: 60)), ahora: base);
        await repo.leer(ahora: base);
        await repo.olvidar(ana);
        await repo.olvidarTodo();

        expect(salida.lineas, isNotEmpty, reason: 'tiene que haber avisado de la falla');
        final todo = salida.lineas.join('\n');
        expect(todo, isNot(contains(ana)));
        expect(todo, isNot(contains('@')));
      },
    );

    test('el caso de uso que guarda el candado no deja la dirección en su toString() ni con '
        'EquatableConfig.stringify en true', () {
      final previo = EquatableConfig.stringify;
      addTearDown(() => EquatableConfig.stringify = previo);
      EquatableConfig.stringify = true;

      final params = RegistrarBloqueoReenvioVerificacionParams(correo: ana, ahora: base);
      final envio = RegistrarEnvioVerificacionParams(correo: ana, ahora: base);

      expect('$params', isNot(contains(ana)));
      expect('$envio', isNot(contains(ana)));
    });
  });
}
