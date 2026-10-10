// #319 (seguimiento de #278, HU-AUTH-008 y HU-AUTH-010): una respuesta lenta del estado de cuenta no
// reescribe lo que «Borrar datos locales» borró ni deja en el único lugar donde se recuerda el
// estado de otra cuenta. Con el cableado real: sesión, custodia, repositorio y notifier.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/secure_storage/secure_storage_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/db_local_repository_en_memoria.dart';

/// Un servidor que contesta cuando el test lo decide, pedido por pedido.
final class _ServidorManual implements EstadoCuentaRemoteDataSource {
  final pedidos = <Completer<EstadoCuenta>>[];

  @override
  Future<EstadoCuenta> consultar() {
    final pedido = Completer<EstadoCuenta>();
    pedidos.add(pedido);
    return pedido.future;
  }
}

const _clave = ClaveSegura.estadoCuenta;

void main() {
  late Directory directorio;
  late AlmacenSeguroEnMemoria almacen;
  late _ServidorManual servidor;
  late ProviderContainer container;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('estado_cuenta_319_');
    almacen = AlmacenSeguroEnMemoria();
    servidor = _ServidorManual();
    container = ProviderContainer(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(
            credenciales: const {'ana@example.com': 'secreto123', 'beto@example.com': 'secreto123'},
          ),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        asignacionCampaniaDataSourceProvider.overrideWithValue(AsignacionCampaniaEnMemoria()),
        almacenSeguroProvider.overrideWithValue(almacen),
        archivoEnvoltorioDekProvider.overrideWithValue(
          ArchivoEnvoltorioDek(directorio: () async => directorio),
        ),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(servidor),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(EstadoCuentaEnAlmacen(almacen)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await directorio.exists()) await directorio.delete(recursive: true);
  });

  Future<String> entrar(String email) async {
    await container.read(sesionProvider.future);
    final falla = await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: email, password: 'secreto123');
    expect(falla, isNull);
    return container.read(sesionProvider).value!.usuarioId;
  }

  /// Deja que el notifier arranque su consulta: el pedido queda en vuelo en `servidor.pedidos`.
  Future<void> arrancarLaConsulta() async {
    container.listen(estadoCuentaProvider, (_, _) {});
    await pumpEventQueue();
  }

  Future<void> cerrarSesion() async {
    await container.read(sesionProvider.notifier).cerrarSesion();
    await pumpEventQueue();
  }

  group('el estado de cuenta que llega tarde (#319)', () {
    test('dado que se borraron los datos locales con la consulta en vuelo, cuando la respuesta '
        'llega, no reescribe lo borrado', () async {
      await entrar('ana@example.com');
      await arrancarLaConsulta();
      expect(servidor.pedidos, hasLength(1));
      await almacen.escribir(_clave, 'recordado-antes');

      await container.read(custodiaClaveDbProvider).olvidarDatosDelUsuario();
      servidor.pedidos.single.complete(EstadoCuenta.activa);
      await pumpEventQueue();

      expect(almacen.contenido.containsKey(_clave), isFalse);
    });

    test('dado que la persona sale y entra otra cuenta con la consulta en vuelo, la respuesta de '
        'la primera no queda en el lugar de la segunda', () async {
      await entrar('ana@example.com');
      await arrancarLaConsulta();
      expect(servidor.pedidos, hasLength(1));
      await cerrarSesion();

      final beto = await entrar('beto@example.com');
      await pumpEventQueue();
      expect(servidor.pedidos, hasLength(2), reason: 'la cuenta nueva consulta la suya');
      servidor.pedidos[1].complete(EstadoCuenta.activa);
      await pumpEventQueue();
      servidor.pedidos[0].complete(EstadoCuenta.suspendida);
      await pumpEventQueue();

      expect(almacen.contenido[_clave], '$beto:activa');
      expect(container.read(estadoCuentaProvider).value, EstadoCuenta.activa);
    });

    test('dado que la persona sale y la consulta sigue en vuelo, la respuesta no deja su estado '
        'recordado para nadie', () async {
      await entrar('ana@example.com');
      await arrancarLaConsulta();
      await cerrarSesion();

      servidor.pedidos.single.complete(EstadoCuenta.suspendida);
      await pumpEventQueue();

      expect(almacen.contenido.containsKey(_clave), isFalse);
    });

    test('dado el mismo usuario y los datos de siempre, la respuesta se recuerda', () async {
      final ana = await entrar('ana@example.com');
      await arrancarLaConsulta();

      servidor.pedidos.single.complete(EstadoCuenta.activa);
      await pumpEventQueue();

      expect(almacen.contenido[_clave], '$ana:activa');
      expect(container.read(estadoCuentaProvider).value, EstadoCuenta.activa);
    });

    test('dado que se borraron los datos y después se consulta de nuevo, la consulta nueva sí se '
        'recuerda', () async {
      final ana = await entrar('ana@example.com');
      await arrancarLaConsulta();
      await container.read(custodiaClaveDbProvider).olvidarDatosDelUsuario();
      servidor.pedidos.single.complete(EstadoCuenta.activa);
      await pumpEventQueue();

      final falla = container.read(estadoCuentaProvider.notifier).refrescar();
      await pumpEventQueue();
      expect(servidor.pedidos, hasLength(2));
      servidor.pedidos[1].complete(EstadoCuenta.activa);

      expect(await falla, isNull);
      expect(almacen.contenido[_clave], '$ana:activa');
    });

    test('dado que otra cuenta tomó la sesión mientras «Actualizar» esperaba, lo que vuelve no '
        'cambia el estado de la cuenta nueva', () async {
      await entrar('ana@example.com');
      await arrancarLaConsulta();
      servidor.pedidos[0].complete(EstadoCuenta.activa);
      await pumpEventQueue();
      final actualizar = container.read(estadoCuentaProvider.notifier).refrescar();
      await pumpEventQueue();
      expect(servidor.pedidos, hasLength(2));
      await cerrarSesion();
      await entrar('beto@example.com');
      await pumpEventQueue();
      expect(servidor.pedidos, hasLength(3));
      servidor.pedidos[2].complete(EstadoCuenta.pendienteAsignacion);
      await pumpEventQueue();

      servidor.pedidos[1].complete(EstadoCuenta.suspendida);

      expect(await actualizar, isNull);
      expect(container.read(estadoCuentaProvider).value, EstadoCuenta.pendienteAsignacion);
    });
  });

  group('generacionDatosLocalesProvider (#319)', () {
    test('dado un borrado de datos por la custodia, la generación que lee el repositorio es la '
        'misma que avanzó', () async {
      final generacion = container.read(generacionDatosLocalesProvider);
      final antes = generacion.valor;

      await container.read(custodiaClaveDbProvider).olvidarDatosDelUsuario();

      expect(container.read(generacionDatosLocalesProvider).valor, isNot(antes));
      expect(container.read(generacionDatosLocalesProvider), same(generacion));
    });
  });
}
