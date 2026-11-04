// QA de la baja de persona (HU-UBI-011, #143, PR #485) de punta a punta con la base real: la pantalla de
// clientes del depto (real), la hoja «¿Dar de baja a …?» (real), los casos de uso, el repositorio y Drift
// en memoria (con la tabla de auditoría local y la cola de sync). Los tests del PR prueban la hoja y la
// pantalla con un repositorio falso y Drift sin pantalla; estos prueban que una persona, tocando, ve lo
// que la HU promete y que del teléfono no se pierde ni se sube nada.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja_persona.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../helpers/logger_mudo.dart';
import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'personas_arnes.dart';
import 'qa_vista32d_baja_143_arnes.dart';

final class _SalidaEnMemoria extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final _t0 = DateTime.utc(2026, 10, 22, 13, 45, 10, 123);

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late PersonaLocalDataSourceDrift local;
  late PersonaRepositoryImpl repositorio;
  late _SalidaEnMemoria salida;
  late ValueNotifier<CuentasFalsas> cuentas;

  Auditoria auditoria() => Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1');

  Persona persona(String id, String nombre, {String apellido = 'Fernández'}) => Persona(
    id: id,
    nombre: nombre,
    apellido: apellido,
    telefono: '099 123 456',
    auditoria: auditoria(),
  );

  /// El teléfono: un edificio con su depto, y dos clientes (Jorge con una nota, María).
  Future<void> armar(WidgetTester tester, {bool espacioDeBaja = false}) async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = PersonaLocalDataSourceDrift(db, encolador: encolador);
    salida = _SalidaEnMemoria();
    repositorio = PersonaRepositoryImpl(local, logger: AppLogger(output: salida));
    cuentas = ValueNotifier(CuentasFalsas());
    final ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    await tester.runAsync(() async {
      await ubicaciones.insertar(
        UbicacionModel(
          id: 'ub-1',
          tipo: TipoUbicacion.edificio,
          calle: 'Mataojo',
          numero: '2044',
          lat: -34.89,
          lon: -56.16,
          ciudadId: 'mvd',
          auditoria: auditoria(),
        ),
      );
      await ubicaciones.insertarEspacio(
        EspacioModel(id: 'esp-1', ubicacionId: 'ub-1', numeroDepto: '101', auditoria: auditoria()),
      );
      for (final (id, nombre) in [('p1', 'Jorge'), ('p2', 'María')]) {
        await local.registrar(
          persona: persona(id, nombre),
          vinculo: EspacioPersona(
            id: 'ep-$id',
            espacioId: 'esp-1',
            personaId: id,
            auditoria: auditoria(),
          ),
          nota: id == 'p1'
              ? NotaPersona(
                  id: 'nota-p1',
                  personaId: 'p1',
                  texto: 'Prefiere de tarde',
                  auditoria: auditoria(),
                )
              : null,
        );
      }
      if (espacioDeBaja) {
        // Se da de baja el depto después de cargar a sus clientes (con el depto de baja no se registra).
        await (db.update(db.espacios)..where((e) => e.id.equals('esp-1'))).write(
          EspaciosCompanion(deletedAt: Value(_t0.add(const Duration(days: 1)))),
        );
      }
      encolador.encolados.clear();
    });
  }

  /// Monta los clientes del depto reales y devuelve el contexto para abrir la hoja encima.
  Future<void> montar(WidgetTester tester, {Size tamano = const Size(390, 844)}) async {
    await cargarFuentes(tester);
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personaRepositoryProvider.overrideWithValue(repositorio),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(contextoActivo()),
          ),
          cuentasDePersonasProvider.overrideWithValue(cuentas.value),
          relojPersonaProvider.overrideWithValue(() => ahoraBaja),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => PersonasDelEspacioPage.abrir(
                    context,
                    espacioId: 'esp-1',
                    colportorId: 'col-1',
                  ),
                  child: const Text('abrir clientes'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir clientes'));
    await asentar(tester);
  }

  /// Abre la hoja de baja de [id] sobre la pantalla de clientes (quien la conecta es la ficha, #141).
  Future<void> abrirHoja(WidgetTester tester, String id, String nombre) async {
    final contexto = tester.element(find.byType(PersonasDelEspacioPage));
    final p = persona(id, nombre);
    // ignore: unawaited_futures
    mostrarHojaBajaPersona(contexto, persona: p);
    await asentar(tester);
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      await armar(tester);
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    });
  }

  Future<int> auditorias(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.auditLogLocal).get()))!.length;

  Future<DateTime?> bajaDe(WidgetTester tester, String id) async => (await tester.runAsync(
    () => (db.select(db.personas)..where((p) => p.id.equals(id))).getSingle(),
  ))!.deletedAt;

  prueba('Escenario «Baja sin pendientes» de punta a punta: Jorge desaparece de la lista, queda el '
      'deleted_at, un evento persona_baja, nada en la cola de sync, y su nota sigue ahí', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('CLIENTES · 2'), findsOneWidget);
    await abrirHoja(tester, 'p1', 'Jorge');

    expect(find.text('¿Dar de baja a Jorge?'), findsOneWidget);
    await tester.tap(find.text('Dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    expect(find.byType(HojaBajaPersona), findsNothing);
    expect(find.text('Jorge Fernández'), findsNothing);
    expect(find.text('CLIENTES · 1'), findsOneWidget);
    expect(await bajaDe(tester, 'p1'), isNotNull);
    expect(await auditorias(tester), 1);
    expect(encolador.encolados, isEmpty, reason: 'la persona es local: nada que subir');
    final notas = await tester.runAsync(() => db.select(db.notas).get());
    expect(notas, hasLength(1), reason: 'el historial se conserva');
    // «Mostrar bajas» aparece y la deja ver con su fecha.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Mostrar bajas'));
    await asentar(tester);
    expect(find.text('Jorge Fernández'), findsOneWidget);
    expect(find.text('Baja el 25/10'), findsOneWidget);
  });

  prueba('Escenario «Baja con EC pendiente» de punta a punta: cancelar o volver no escribe nada; '
      'solo «Sí, dar de baja» da de baja', (tester) async {
    cuentas = ValueNotifier(CuentasFalsas(cuenta: cuentaConSaldo));
    await montar(tester);
    await abrirHoja(tester, 'p2', 'María');

    expect(
      find.text('María te debe \$ 1.200 y tiene 1 entrega pendiente.'.replaceAll('\$ ', '\$ ')),
      findsOneWidget,
    );
    await tester.tap(find.text('Dar de baja igual'));
    await asentar(tester);
    await tester.tap(find.text('No, volver'));
    await asentar(tester);
    await tester.tap(find.text('Cancelar'));
    await asentar(tester);
    expect(await bajaDe(tester, 'p2'), isNull);
    expect(await auditorias(tester), 0);

    await abrirHoja(tester, 'p2', 'María');
    await tester.tap(find.text('Dar de baja igual'));
    await asentar(tester);
    await tester.tap(find.text('Sí, dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    expect(await bajaDe(tester, 'p2'), isNotNull);
    expect(await auditorias(tester), 1);
    expect(find.text('María Fernández'), findsNothing);
  });

  prueba('baja y «Reactivar» de punta a punta: la persona vuelve a la lista, deleted_at nulo, y '
      'cada baja deja su propio evento', (tester) async {
    await montar(tester);
    await abrirHoja(tester, 'p2', 'María');
    await tester.tap(find.text('Dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Mostrar bajas'));
    await asentar(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reactivar'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    expect(find.text('Reactivamos a María.'), findsOneWidget);
    expect(find.text('CLIENTES · 2'), findsOneWidget);
    expect(await bajaDe(tester, 'p2'), isNull);
    expect(encolador.encolados, isEmpty);

    // Y se puede volver a dar de baja: segundo evento.
    await abrirHoja(tester, 'p2', 'María');
    await tester.tap(find.text('Dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);
    expect(await auditorias(tester), 2);
  });

  prueba('una persona que ya no está en el teléfono: la hoja lo dice y deja salir; en el log solo '
      'el id y el tipo, nunca el nombre ni el teléfono', (tester) async {
    await montar(tester);
    await abrirHoja(tester, 'fantasma', 'Zulema');

    await tester.tap(find.text('Dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    expect(find.text('La persona ya no está en tu teléfono. Volvé atrás.'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    final log = salida.lineas.join('\n');
    expect(log, isNot(contains('Zulema')));
    expect(log, isNot(contains('099 123 456')));
    expect(log, isNot(contains('Fernández')));
  });

  testWidgets('con el espacio dado de baja la hoja no escribe: avisa que es solo lectura y qué '
      'hacer', (tester) async {
    await armar(tester, espacioDeBaja: true);
    await montar(tester);
    await abrirHoja(tester, 'p1', 'Jorge');

    await tester.tap(find.text('Dar de baja'));
    await asentar(tester);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await asentar(tester);

    expect(find.textContaining('Su espacio está dado de baja: solo lectura.'), findsOneWidget);
    expect(find.textContaining('Reactivá el espacio'), findsOneWidget);
    expect(await bajaDe(tester, 'p1'), isNull);
    expect(await auditorias(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  });
}
