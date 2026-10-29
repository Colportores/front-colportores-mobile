// El cableado de los precios (#419): con la base local abierta, la consulta lee la réplica del
// catálogo y los días del aviso fuerte salen de `parametro_global`; sin base, la consulta dice que no
// pudo leer (nunca «no hay precios») y los días son los 15 de siempre.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/catalogo/presentation/providers/precios_providers.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()));
  tearDown(() => db.close());

  ProviderContainer armar(AppDatabase? base) {
    final contenedor = ProviderContainer(
      overrides: [dbLocalProvider.overrideWith(() => _DbFija(base))],
    );
    addTearDown(contenedor.dispose);
    // Los providers de la pantalla son autoDispose: sin quien escuche, se descartan mientras cargan.
    contenedor
      ..listen(catalogoDePreciosProvider('cc-rivera'), (_, _) {})
      ..listen(diasDelAvisoFuerteProvider, (_, _) {});
    return contenedor;
  }

  const fecha = '2026-10-20T12:00:00+00:00';

  Future<void> bajar() => DriftLocalStore(db, entidades: entidadesQueEscribeElMotor).applyDelta(
    {
      'producto': [
        {
          'id': 'pro-1',
          'nombre': 'Conflicto de los Siglos',
          'descripcion': null,
          'tipo': 'LIBRO',
          'es_bonificable': false,
          'es_misionero': false,
          'precio_base_compra': null,
          'casa_editora': null,
          'imagen_url': null,
          'created_at': fecha,
          'updated_at': fecha,
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
          'codigo_editor': 'CS-01',
        },
      ],
      'precio_general': [
        {
          'id': 'pg-1',
          'producto_id': 'pro-1',
          'coleccion_id': null,
          'precio_venta': 45000,
          'valido_desde': '2026-01-01',
          'valido_hasta': null,
          'created_at': fecha,
          'updated_at': fecha,
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
        },
      ],
      'parametro_global': [
        {
          'id': 'par-1',
          'clave': 'dias_antiguedad_precios',
          'valor': 21,
          'created_at': fecha,
          'updated_at': fecha,
          'created_by': null,
          'deleted_at': null,
          'sync_version': 1,
        },
      ],
    },
    scope: 'replica',
    watermark: 'w1',
  );

  test('con la base abierta, el catálogo de la ciudad sale de la réplica local', () async {
    await bajar();
    final contenedor = armar(db);

    final catalogo = await contenedor.read(catalogoDePreciosProvider('cc-rivera').future);

    expect(catalogo.productos.single.nombre, 'Conflicto de los Siglos');
    expect(catalogo.productos.single.codigoEditor, 'CS-01');
    expect(catalogo.generales.single.centavos, 45000);
  });

  test('con la base abierta, los días del aviso fuerte salen de parametro_global', () async {
    await bajar();
    final contenedor = armar(db);

    expect(await contenedor.read(diasDelAvisoFuerteProvider.future), 21);
  });

  test('con la base abierta pero sin parámetro bajado todavía, los días son 15', () async {
    final contenedor = armar(db);

    expect(await contenedor.read(diasDelAvisoFuerteProvider.future), 15);
  });

  test('sin base abierta, los precios dicen que no se pudieron leer y los días son 15', () async {
    final contenedor = armar(null);

    await expectLater(
      contenedor.read(catalogoDePreciosProvider('cc-rivera').future),
      throwsA(isA<FailurePreciosNoDisponibles>()),
    );
    expect(await contenedor.read(diasDelAvisoFuerteProvider.future), 15);
  });
}
