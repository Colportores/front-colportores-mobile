// Dobles y semillas de la entrega diferida (HU-VEN-003, #435): lo que falta entregar, las respuestas
// del repositorio y un arnés que abre «Entregar otro día», «Entregas pendientes» y «Marcar entregado»
// desde una pantalla de partida (así se prueba volver y reentrar).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/entrega_diferida_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'campo_falsos.dart' show agendaDe;
import 'entrega_falsos.dart';
import 'venta_ui_falsos.dart' show asentar;

/// Quién y dónde es cada vínculo en los tests (clave: `espacioPersonaId`).
const rotulosDeLosTests = <String, RotuloDeEntrega>{
  'ep-1': (persona: 'María Fernández', direccion: 'Grecia 3310'),
  'ep-2': (persona: 'Juan Pérez', direccion: 'Mataojo 2044 · 3B'),
  'ep-3': (persona: 'Ana Silva', direccion: 'Bvar. Artigas 1500'),
};

/// «Hoy» de los tests: miércoles 28/10 al mediodía, hora local (así nada depende del huso del equipo).
DateTime get ahoraDeLosTests => DateTime(2026, 10, 28, 12);

LineaPendiente lineaDe(String entregaId, String productoId, [int cantidad = 1]) =>
    LineaPendiente(entregaId: entregaId, productoId: productoId, cantidad: cantidad);

/// Lo que falta entregar de la venta [ventaId]: por defecto «Salud y Hogar» y «Nuestros Hijos».
EntregaPendiente pendienteDe(
  String ventaId, {
  DateTime? fecha,
  List<LineaPendiente>? lineas,
  String vinculo = 'ep-1',
  String talonario = '0042',
  String? espacioId = 'esp-1',
}) => EntregaPendiente(
  ventaId: ventaId,
  espacioPersonaId: vinculo,
  lineas: lineas ?? [lineaDe('e-$ventaId-1', 'p-salud'), lineaDe('e-$ventaId-2', 'p-hijos')],
  fechaPrevista: fecha,
  espacioId: espacioId,
  numeroTalonario: talonario,
);

/// Lo que responde el repositorio al diferir: la cita ENTREGA de [fecha].
EntregaDiferida diferidaPara(DateTime fecha, {String ventaId = 'v-1'}) => EntregaDiferida(
  entregas: [entregaDe('e-1', 'p-salud', pendiente: true, fechaPrevista: fecha)],
  cita: agendaDe(
    'c-1',
    tipo: TipoAgenda.entrega,
    ventaId: ventaId,
    entregaId: 'e-1',
    fecha: fecha.toUtc(),
  ),
  direccion: 'Grecia 3310',
);

/// Lo que responde el repositorio al cumplir: [quedan] filas siguen pendientes.
EntregaCumplida cumplidaCon({List<Entrega> quedan = const [], bool yaEstaba = false}) =>
    EntregaCumplida(
      entregas: [entregaDe('e-1', 'p-salud'), ...quedan],
      entregadas: yaEstaba ? const [] : [entregaDe('e-1', 'p-salud')],
      yaEstaba: yaEstaba,
    );

/// Cómo se cerró la pantalla que se abrió.
final class SalidaDePantalla<T> {
  T? valor;
  var cerrada = false;
}

/// Los overrides de los tests de la entrega diferida: el repositorio, el reloj, los ids y los rótulos.
List<Override> overridesDeEntregaDiferida(
  EntornoDeEntrega e, {
  Map<String, RotuloDeEntrega> rotulos = rotulosDeLosTests,
}) => [
  ...e.overrides,
  rotuloDeEntregaProvider.overrideWith(
    (ref, quien) async => rotulos[quien.espacioPersonaId] ?? (persona: '', direccion: ''),
  ),
];

/// Monta una pantalla de partida con un botón «abrir» que empuja [ruta]; si [abrir], la abre.
Future<SalidaDePantalla<T>> montarPantalla<T>(
  WidgetTester tester,
  EntornoDeEntrega e,
  Route<T> Function() ruta, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  e.ahora = ahoraDeLosTests;
  final salida = SalidaDePantalla<T>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...overridesDeEntregaDiferida(e), ...extra],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_pantalla'),
                onPressed: () async {
                  final r = await Navigator.of(context).push<T>(ruta());
                  salida.valor = r;
                  salida.cerrada = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirPantalla(tester);
  return salida;
}

Future<void> abrirPantalla(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_pantalla')));
  await asentar(tester);
}
