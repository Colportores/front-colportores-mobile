// Los misioneros que se ofrecen en «Lo que dejaste» (#608): los productos vivos de categoría
// MISIONEROS de la réplica local del catálogo, por nombre.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/misioneros_para_dejar_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/misionero_dejado.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';
import '../../../../../helpers/replica_de_catalogo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo()));
  tearDown(() => db.close());

  test('solo los misioneros vivos, ordenados por nombre', () async {
    await ReplicaDeCampanias(db).bajar({
      'producto': [
        filaProducto('p-paz', 'Paz en tiempos de crisis', categoria: 'MISIONEROS', misionero: true),
        filaProducto('p-camino', 'El camino a Cristo', categoria: 'MISIONEROS', misionero: true),
        filaProducto('p-viejo', 'Aa misionero de baja', categoria: 'MISIONEROS', baja: true),
        filaProducto('p-vida', 'Vida Feliz', categoria: 'REVISTAS'),
        filaProducto('p-salud', 'Salud y Hogar', categoria: 'BONIFICABLES'),
        filaProducto('p-sin', 'Sin categoría', categoria: null),
      ],
    });

    final leidos = await MisionerosParaDejarDrift(db).leer();

    expect(leidos, const [
      MisioneroParaDejar(productoId: 'p-camino', nombre: 'El camino a Cristo'),
      MisioneroParaDejar(productoId: 'p-paz', nombre: 'Paz en tiempos de crisis'),
    ]);
  });

  test('sin catálogo en el teléfono no hay ninguno (el paso no aparece)', () async {
    expect(await MisionerosParaDejarDrift(db).leer(), isEmpty);
  });
}
