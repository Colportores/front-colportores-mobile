// QA de #509 de punta a punta con la base real (Drift en memoria): la pantalla de notas de una persona
// y «Ver borradas» reales, el repositorio real, y la limpieza real corrida con la pantalla abierta.
// Los tests del PR prueban la pantalla con un repositorio falso y la limpieza sin pantalla; estos prueban
// que lo que la persona ve y lo que queda en el teléfono coinciden, que las notas de un lugar y las
// activas no se tocan, y que el registro no lleva el texto de una nota ni la sentencia.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/nota_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_borradas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/limpieza_notas_borradas_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/nota_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/limpiar_notas_borradas_use_case.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/notas_de_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../helpers/logger_mudo.dart';
import 'notas_persona_arnes.dart' show asentar;

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  // «Hoy»: 22/10/2026 a las 15:00 UTC.
  final ahora = DateTime.utc(2026, 10, 22, 15);
  DateTime haceDias(int d, {int horas = 0}) => ahora.subtract(Duration(days: d, hours: horas));

  late AppDatabase db;
  late _Salida salida;
  late NotaPersonaRepositoryImpl repo;

  Auditoria aud() =>
      Auditoria(createdAt: haceDias(300), updatedAt: haceDias(300), createdBy: 'col-1');

  Future<void> sembrarPersona(WidgetTester tester) => tester.runAsync(() async {
    final encolador = EncoladorSyncEnMemoria();
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    await ubicaciones.insertar(
      UbicacionModel(
        id: 'ub-1',
        tipo: TipoUbicacion.edificio,
        calle: 'Mataojo',
        numero: '2044',
        lat: -34.89,
        lon: -56.16,
        ciudadId: 'mvd',
        auditoria: aud(),
      ),
    );
    await ubicaciones.insertarEspacio(
      EspacioModel(id: 'esp-1', ubicacionId: 'ub-1', numeroDepto: '3B', auditoria: aud()),
    );
    await PersonaLocalDataSourceDrift(db, encolador: encolador).registrar(
      persona: Persona(id: 'per-1', nombre: 'María', apellido: 'Fernández', auditoria: aud()),
      vinculo: EspacioPersona(id: 'ep-1', espacioId: 'esp-1', personaId: 'per-1', auditoria: aud()),
    );
  });

  Future<void> sembrarNota(
    WidgetTester tester,
    String id,
    String texto, {
    DateTime? borrada,
    String tipo = TipoObjetivoNota.persona,
    String objetivo = 'per-1',
  }) => tester.runAsync(
    () => db
        .into(db.notas)
        .insert(
          NotasCompanion.insert(
            id: id,
            targetType: tipo,
            targetId: objetivo,
            texto: texto,
            createdAt: haceDias(300),
            updatedAt: haceDias(300),
            createdBy: const Value('col-1'),
            deletedAt: Value(borrada),
          ),
        ),
  );

  Future<List<String>> idsEnLaBase(WidgetTester tester) async => (await tester.runAsync(
    () async => [for (final n in await db.select(db.notas).get()) n.id]..sort(),
  ))!;

  Future<void> limpiar(WidgetTester tester, {DateTime? en, AppLogger? logger}) async {
    final caso = LimpiarNotasBorradasUseCase(
      LimpiezaNotasBorradasRepositoryImpl(
        NotasBorradasLocalDataSourceDrift(db),
        logger: logger ?? AppLogger(output: salida),
      ),
      ahora: () async => en ?? ahora,
    );
    await tester.runAsync(() => caso(const NoParams()));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await asentar(tester);
  }

  Future<void> montar(WidgetTester tester, {Size tamano = const Size(390, 844)}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notaPersonaRepositoryProvider.overrideWithValue(repo),
          relojPersonaProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      NotasDePersonaPage.abrir(context, personaId: 'per-1', colportorId: 'col-1'),
                  child: const Text('abrir notas'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir notas'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      salida = _Salida();
      repo = NotaPersonaRepositoryImpl(
        NotaPersonaLocalDataSourceDrift(db),
        logger: AppLogger(output: salida),
      );
      await sembrarPersona(tester);
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    });
  }

  prueba('dadas notas de 89 y 91 días borradas, «Ver borradas» muestra solo la de 89 y la limpieza '
      'borra solo la de 91; la activa, la de un lugar y la restaurada no se tocan', (tester) async {
    await sembrarNota(tester, 'activa', 'Sigue activa.');
    await sembrarNota(tester, 'vieja91', 'Pasó el plazo.', borrada: haceDias(91));
    await sembrarNota(tester, 'ayer89', 'Casi se va.', borrada: haceDias(89));
    await sembrarNota(
      tester,
      'lugar200',
      'Portón roto.',
      borrada: haceDias(200),
      tipo: TipoObjetivoNota.ubicacion,
      objetivo: 'ub-1',
    );
    await montar(tester);

    // Antes de limpiar: la de 91 ya no cuenta ni se ve (aunque siga en la base).
    expect(find.text('Ver borradas (1)'), findsOneWidget);
    await tester.tap(find.text('Ver borradas (1)'));
    await asentar(tester);
    expect(find.text('Casi se va.'), findsOneWidget);
    expect(find.text('Pasó el plazo.'), findsNothing);
    expect(
      find.text('Se borra el 23/10'),
      findsOneWidget,
      reason: '89 d + 1 d = 90 d: mañana 23/10',
    );
    expect(await idsEnLaBase(tester), ['activa', 'ayer89', 'lugar200', 'vieja91']);

    // Corre la limpieza con la pantalla abierta.
    await limpiar(tester);
    expect(await idsEnLaBase(tester), ['activa', 'ayer89', 'lugar200']);
    expect(find.text('Casi se va.'), findsOneWidget, reason: 'la lista no parpadea ni se vacía');
    expect(find.byKey(ClavesNotas.seBorraEl), findsOneWidget);
    expect(salida.lineas.join('\n'), isNot(contains('Casi se va')));
    expect(salida.lineas.join('\n'), isNot(contains('Pasó el plazo')));
  });

  prueba('dada una nota restaurada el último día, la limpieza no la toca; si se borra de nuevo, '
      'empieza otra vez los 90 días', (tester) async {
    await sembrarNota(tester, 'ultimo', 'La salvo a tiempo.', borrada: haceDias(89, horas: 23));
    await montar(tester);
    await tester.tap(find.text('Ver borradas (1)'));
    await asentar(tester);
    await tester.tap(find.text('Restaurar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);
    expect(find.text('No hay notas borradas.'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver').first);
    await asentar(tester);
    expect(find.text('La salvo a tiempo.'), findsOneWidget);
    expect(find.textContaining('Ver borradas'), findsNothing);

    // Dos meses después: la nota activa no se va aunque haya estado borrada.
    await limpiar(tester, en: ahora.add(const Duration(days: 60)));
    expect(await idsEnLaBase(tester), ['ultimo']);
  });

  prueba('dada una limpieza con la hora del teléfono atrasada o igual, no borra nada de más', (
    tester,
  ) async {
    await sembrarNota(tester, 'b60', 'A los 60 días.', borrada: haceDias(60));
    await montar(tester);
    await limpiar(tester, en: ahora.subtract(const Duration(days: 365)));
    expect(await idsEnLaBase(tester), ['b60']);
    await limpiar(tester, en: haceDias(60).add(const Duration(days: 90)));
    expect(await idsEnLaBase(tester), ['b60'], reason: 'justo a los 90 días todavía está');
    await limpiar(tester, en: haceDias(60).add(const Duration(days: 90, milliseconds: 1)));
    expect(await idsEnLaBase(tester), isEmpty);
  });

  prueba('dada una base que falla, la limpieza no deja escapar la sentencia ni el texto de la nota '
      'en el registro (privacidad)', (tester) async {
    await sembrarNota(tester, 'secreta', 'TEXTO-SECRETO-123', borrada: haceDias(200));
    await tester.runAsync(() => db.customStatement('ALTER TABLE nota RENAME TO nota_nota'));
    await limpiar(tester);
    final log = salida.lineas.join('\n');
    expect(log, contains('NOTAS_BORRADAS_PURGA_FAIL'));
    expect(log, isNot(contains('TEXTO-SECRETO')));
    expect(log, isNot(contains('DELETE')));
    expect(log, isNot(contains('SELECT')));
  });

  prueba('dada una limpieza que borra notas con texto, el registro lleva la cantidad y no el '
      'texto', (tester) async {
    await sembrarNota(tester, 'a', 'TEXTO-SECRETO-ABC', borrada: haceDias(100));
    await sembrarNota(tester, 'b', 'OTRO-SECRETO-XYZ', borrada: haceDias(120));
    await limpiar(tester);
    final log = salida.lineas.join('\n');
    expect(log, contains('NOTAS_BORRADAS_PURGA'));
    expect(log, contains('2'));
    expect(log, isNot(contains('SECRETO')));
    expect(await idsEnLaBase(tester), isEmpty);
  });
}
