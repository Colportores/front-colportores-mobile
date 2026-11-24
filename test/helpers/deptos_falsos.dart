// Los deptos de un edificio en la hoja de la casa (vista 39, C·09 y C·10, #452), sin base de datos: la
// lista de deptos y su resumen. Para los tests que montan la hoja de un edificio y abren un depto.
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'espacios_falsos.dart';

/// El depto 3B (`esp-3B`, piso 3) de un edificio.
final depto3B = espacioDe('esp-3B', '3B', piso: '3', ubicacionId: 'u-1');

/// Los overrides que le dan a la hoja de un edificio sus [deptos] (por defecto, el 3B) y el resumen de
/// cada uno (por defecto, ninguno: las filas no dicen estado).
List<Override> overridesDeptos({
  List<Espacio>? deptos,
  Map<String, ResumenDelDepto> resumen = const {},
}) => [
  espaciosDeUbicacionProvider.overrideWith((ref, ubicacionId) async => deptos ?? [depto3B]),
  resumenDeLosDeptosProvider.overrideWith((ref, clave) => Stream.value(resumen)),
];

/// Toca el depto [espacioId] en la lista de deptos de la hoja (C·09) y deja que la hoja lo abra como
/// una casa (C·10).
Future<void> abrirDepto(WidgetTester tester, [String espacioId = 'esp-3B']) async {
  final fila = find.byKey(ClavesDeptosDeLaCasa.fila(espacioId));
  await tester.ensureVisible(fila);
  await tester.pump();
  await tester.tap(fila);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
