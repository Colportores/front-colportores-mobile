// Los nombres de lo vendido para «Entregar ahora» (27B·01, #432), leídos de la réplica local del
// catálogo: sin esto la pantalla de la entrega siempre mostraba el error de lectura.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/data/services/fuente_de_productos_de_la_entrega_local.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';
import '../../../../../helpers/replica_de_catalogo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  FuenteDeProductosDeLaEntregaLocal fuente() =>
      FuenteDeProductosDeLaEntregaLocal(db, logger: loggerMudo());

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
  });
  tearDown(() => db.close());

  final catalogo = <String, List<Map<String, Object?>>>{
    'producto': [
      filaProducto('p-camino', 'El camino a Cristo', categoria: 'MISIONEROS', misionero: true),
      filaProducto('p-vida', 'Vida Feliz', categoria: 'REVISTAS'),
      filaProducto('p-salud', 'Salud y Hogar', categoria: 'BONIFICABLES'),
      filaProducto('p-viejo', 'Libro de baja', baja: true),
    ],
    'coleccion': [filaCombo('k-2', 'Colección de 2 libros', aElegir: 2)],
    'producto_coleccion': [
      filaComponente('pc-1', 'p-camino', 'k-2'),
      filaComponente('pc-2', 'p-vida', 'k-2'),
      filaComponente('pc-3', 'p-salud', 'k-2', baja: true),
    ],
  };

  Future<ProductosDeLaEntrega> leer({
    Set<String> productos = const {},
    Set<String> combos = const {},
  }) async {
    final r = await fuente().leer(productoIds: productos, comboIds: combos);
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  test('los nombres de lo vendido, también de un producto dado de baja', () async {
    await replica.bajar(catalogo);
    await replica.terminoUnPull();

    final leido = await leer(productos: {'p-salud', 'p-viejo'});

    expect(leido.nombres, {'p-salud': 'Salud y Hogar', 'p-viejo': 'Libro de baja'});
  });

  test('la base del combo son sus componentes vivos', () async {
    await replica.bajar(catalogo);
    await replica.terminoUnPull();

    final leido = await leer(combos: {'k-2'});

    expect(leido.baseDeCombos, {
      'k-2': {'p-camino', 'p-vida'},
    });
  });

  test('un producto que el teléfono no conoce queda sin nombre (no se inventa)', () async {
    await replica.bajar(catalogo);
    await replica.terminoUnPull();

    final leido = await leer(productos: {'p-salud', 'p-no-esta'});

    expect(leido.nombres.containsKey('p-no-esta'), isFalse);
    expect(leido.nombres['p-salud'], 'Salud y Hogar');
  });

  test('sin ningún pull terminado: falla de lectura, con «Reintentar»', () async {
    await replica.bajar(catalogo);

    final r = await fuente().leer(productoIds: {'p-salud'}, comboIds: const {});

    expect(r.swap().getOrElse(() => throw StateError('')), isA<FailureEntregaNoDisponible>());
  });
}
