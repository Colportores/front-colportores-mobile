// Arnés de los tests de cancelar una agenda (HU-VIS-004, vista 23C·04 y 23C·05): una lista de prueba
// con un botón que abre un detalle de prueba, y en el detalle el enlace «Cancelar agenda» real. El
// detalle de verdad (23C·01) es de #409; acá solo tiene el estado de la agenda y el enlace al pie.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/enlace_cancelar_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_cancelar_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';

/// El instante «ahora» de los tests de cancelar.
final ahoraCancelar = DateTime.utc(2026, 10, 26, 18, 30);

const idAgendaCancelar = 'age-1';

/// Deja correr los fotogramas (las hojas, los avisos y los cierres animan).
Future<void> asentarCancelacion(WidgetTester tester, [int veces = 14]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Lo que el arnés deja ver al test.
final class ArnesCancelar {
  ArnesCancelar({required this.repositorio, required this.recordatorios});

  final AgendaRepositorioFalso repositorio;
  final RecordatoriosEnMemoria recordatorios;

  /// Cuántas veces se abrió el detalle de prueba.
  var aperturasDelDetalle = 0;

  /// Cada resultado con el que el detalle recibió `alCancelar`.
  final cancelaciones = <bool>[];

  /// El estado de la agenda que dibuja el detalle (el test lo cambia con [cambiarEstado]).
  final estado = ValueNotifier(EstadoAgenda.programada);

  void cambiarEstado(EstadoAgenda nuevo) => estado.value = nuevo;
}

/// El enlace tal como lo toca la colportora: el texto «Cancelar agenda» del detalle (no el de la hoja).
Finder get enlaceCancelar =>
    find.descendant(of: find.byType(EnlaceCancelarAgenda), matching: find.text('Cancelar agenda'));

/// Los botones de la hoja abierta.
Finder get hoja => find.byType(HojaCancelarAgenda);
Finder get botonCancelarDeLaHoja => find.descendant(of: hoja, matching: find.byType(FilledButton));
Finder get botonVolverDeLaHoja => find.descendant(of: hoja, matching: find.byType(OutlinedButton));

/// Monta una lista de prueba y, si [abrirDetalle], entra al detalle de prueba (con el enlace al pie).
///
/// - [cierraAlCancelar]: el detalle se cierra solo (lo que hace `EnlaceCancelarAgenda` sin
///   `alCancelar`). Con `false` el detalle se queda y repinta con la agenda `CANCELADA`.
/// - [escala]: el `textScaler` de toda la app.
Future<ArnesCancelar> montarCancelacion(
  WidgetTester tester, {
  AgendaRepositorioFalso? repositorio,
  RecordatoriosEnMemoria? recordatorios,
  TipoAgenda tipo = TipoAgenda.entrevista,
  EstadoAgenda estado = EstadoAgenda.programada,
  bool cierraAlCancelar = true,
  bool abrirDetalle = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final arnes = ArnesCancelar(
    repositorio: repositorio ?? AgendaRepositorioFalso(),
    recordatorios: recordatorios ?? RecordatoriosEnMemoria(),
  );
  arnes.estado.value = estado;
  await arnes.recordatorios.programar(
    RecordatorioDeVisita(
      agendaId: idAgendaCancelar,
      tipo: tipo,
      direccion: 'Av. Italia 1234',
      fechaProgramada: DateTime.utc(2026, 10, 27, 17),
    ),
  );
  arnes.recordatorios.llamadas.clear();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(arnes.repositorio),
        recordatoriosProvider.overrideWithValue(arnes.recordatorios),
        relojVisitaProvider.overrideWithValue(() => ahoraCancelar),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Lista de agendas'),
                  TextButton(
                    onPressed: () {
                      arnes.aperturasDelDetalle += 1;
                      unawaited(
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => _DetalleDePrueba(
                              arnes: arnes,
                              tipo: tipo,
                              cierra: cierraAlCancelar,
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('abrir detalle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrirDetalle) {
    await tester.tap(find.text('abrir detalle'));
    await asentarCancelacion(tester);
  }
  return arnes;
}

class _DetalleDePrueba extends StatelessWidget {
  const _DetalleDePrueba({required this.arnes, required this.tipo, required this.cierra});

  final ArnesCancelar arnes;
  final TipoAgenda tipo;
  final bool cierra;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de prueba')),
      body: ValueListenableBuilder(
        valueListenable: arnes.estado,
        builder: (context, estado, _) => Column(
          children: [
            Expanded(child: Center(child: Text('Estado: ${estado.codigo}'))),
            EnlaceCancelarAgenda(
              agendaId: idAgendaCancelar,
              tipo: tipo,
              estado: estado,
              alCancelar: cierra
                  ? null
                  : (r) {
                      arnes.cancelaciones.add(r.recordatorioCancelado);
                      arnes.cambiarEstado(EstadoAgenda.cancelada);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
