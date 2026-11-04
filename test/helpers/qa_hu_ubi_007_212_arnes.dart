// Arnés de la QA de HU-UBI-007 (#212): la DB local en memoria con la cola de sync y las pantallas
// reales (hoja de la ubicación, hoja del depto, clientes del depto). Copia, con nombres públicos, el
// armado del test del PR #501 para que lo reusen los archivos de QA.
// (#290): su escenario se prueba contra los datos (ni se sube ni sale del teléfono).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'logger_mudo.dart';

/// Una DB que ya está «abierta»: los providers solo necesitan el `AppDatabase`.
class DbFija extends DbLocalNotifier {
  DbFija(this._base);

  final AppDatabase _base;

  @override
  AppDatabase? build() => _base;
}

final t0212 = DateTime.utc(2026, 10, 20, 10);
final hoy212 = DateTime.utc(2026, 10, 27, 15);

/// Un UUID v7: la versión en el tercer grupo y la variante RFC en el cuarto.
final uuidV7212 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Lo que la HU dice, letra por letra.
const avisoDosPersonas212 =
    'Este espacio tiene 2 personas. Sus datos se conservarán pero el espacio quedará marcado como '
    'baja.';
const avisoUnaPersona212 =
    'Este espacio tiene 1 persona. Sus datos se conservarán pero el espacio quedará marcado como '
    'baja.';
const bloqueo212 =
    'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las personas '
    'primero.';

/// Las columnas de `public.espacio` en el servidor (backend 0104): lo único que puede subir.
const columnas212 = {
  'id',
  'ubicacion_id',
  'numero_depto',
  'piso',
  'created_at',
  'updated_at',
  'created_by',
  'deleted_at',
  'sync_version',
};

/// El teléfono de un test: la DB local, el motor de mentira y los accesos que siembran datos.
final class Telefono212 {
  Telefono212() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    personas = PersonaLocalDataSourceDrift(db, encolador: encolador);
  }

  late final AppDatabase db;
  late final EncoladorSyncEnMemoria encolador;
  late final UbicacionLocalDataSourceDrift ubicaciones;
  late final PersonaLocalDataSourceDrift personas;

  Auditoria get auditoria => Auditoria(createdAt: t0212, updatedAt: t0212, createdBy: 'col-1');

  Future<void> ubicacion(
    String id, {
    TipoUbicacion tipo = TipoUbicacion.edificio,
    String calle = 'Mataojo',
    String numero = '2044',
  }) => ubicaciones.insertar(
    UbicacionModel(
      id: id,
      tipo: tipo,
      calle: calle,
      numero: numero,
      lat: -34.89,
      lon: -56.16,
      ciudadId: 'mvd',
      auditoria: auditoria,
    ),
  );

  Future<void> depto(String id, String? numero, {String ubicacionId = 'ub-1', String? piso}) =>
      ubicaciones.insertarEspacio(
        EspacioModel(
          id: id,
          ubicacionId: ubicacionId,
          numeroDepto: numero,
          piso: piso,
          auditoria: auditoria,
        ),
      );

  Future<void> persona(String id, String nombre, {required String espacioId}) => personas.registrar(
    persona: Persona(id: id, nombre: nombre, apellido: 'Gómez', auditoria: auditoria),
    vinculo: EspacioPersona(
      id: 'ep-$id',
      espacioId: espacioId,
      personaId: id,
      auditoria: auditoria,
    ),
  );

  Future<void> espacioDeLaCasa(String id, String ubicacionId) => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(
          id: id,
          ubicacionId: ubicacionId,
          createdAt: t0212,
          updatedAt: t0212,
          createdBy: const Value('col-1'),
        ),
      );

  /// Lo sembrado no cuenta como lo que hizo la persona: la cola arranca vacía.
  void limpiarCola() => encolador.encolados.clear();

  Iterable<CambioEncolado> deptosEncolados() =>
      encolador.encolados.where((c) => c.entidad == 'espacio');
}

/// El teléfono del test en curso.
late Telefono212 tel212;

AppDatabase get db212 => tel212.db;

/// Deja correr lo que es de verdad asincrónico (SQLite) y los cuadros que dibujan lo que llegó.
Future<void> drenar212(WidgetTester tester, [int vueltas = 5]) async {
  for (var i = 0; i < vueltas; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Corre [accion] fuera del reloj falso de `testWidgets` (lecturas y escrituras directas a la DB).
Future<T> real212<T>(WidgetTester tester, Future<T> Function() accion) async =>
    (await tester.runAsync(accion)) as T;

/// Todas las filas de `espacio`, bajas incluidas.
Future<List<EspacioFila>> espacios212(WidgetTester tester) =>
    real212(tester, () => db212.select(db212.espacios).get());

Future<EspacioFila> espacio212(WidgetTester tester, String id) async =>
    (await espacios212(tester)).singleWhere((e) => e.id == id);

Future<List<PersonaFila>> personas212(WidgetTester tester) =>
    real212(tester, () => db212.select(db212.personas).get());

Future<List<EspacioPersonaFila>> vinculos212(WidgetTester tester) =>
    real212(tester, () => db212.select(db212.espacioPersonas).get());

/// Monta un anfitrión con un botón por cada pantalla que abre y la DB real detrás.
Future<void> montar212(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  String ubicacionId = 'ub-1',
  String espacioParaClientes = 'esp-1',
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalProvider.overrideWith(() => DbFija(db212)),
        encoladorSyncProvider.overrideWithValue(tel212.encolador),
        relojEspaciosProvider.overrideWithValue(() => hoy212),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => mostrarHojaUbicacion(
                    context,
                    colportorId: 'col-1',
                    ubicacionId: ubicacionId,
                    distanciaMetros: 25,
                  ),
                  child: const Text('abrir hoja'),
                ),
                TextButton(
                  onPressed: () => PersonasDelEspacioPage.abrir(
                    context,
                    espacioId: espacioParaClientes,
                    colportorId: 'col-1',
                  ),
                  child: const Text('abrir clientes'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> abrirHoja212(WidgetTester tester) async {
  await tester.tap(find.text('abrir hoja'));
  await drenar212(tester);
}

/// Cierra la hoja de la ubicación con la ✕ y deja que baje.
Future<void> cerrarHoja212(WidgetTester tester) async {
  await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
  await drenar212(tester);
}

Future<void> tocar212(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await drenar212(tester);
}

/// Un test con el teléfono armado por [sembrar] y cerrado al terminar.
void prueba212(
  String nombre,
  Future<void> Function(WidgetTester tester) cuerpo, {
  Future<void> Function(Telefono212 tel)? sembrar,
}) {
  testWidgets(nombre, (tester) async {
    tel212 = Telefono212();
    await tester.runAsync(() async {
      await sembrar?.call(tel212);
      tel212.limpiarCola();
    });
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(tel212.db.close);
  });
}

/// Un edificio sin espacios.
Future<void> edificioVacio212(Telefono212 t) => t.ubicacion('ub-1');

/// Un edificio con 101 (dos personas) y 102 (sin personas).
Future<void> edificioConDosDeptos212(Telefono212 t) async {
  await t.ubicacion('ub-1');
  await t.depto('esp-1', '101', piso: '1');
  await t.depto('esp-2', '102', piso: '1');
  await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
  await t.persona('p-jorge', 'Jorge', espacioId: 'esp-1');
}

/// Un edificio con un único depto (101) y una persona.
Future<void> edificioConUnDepto212(Telefono212 t) async {
  await t.ubicacion('ub-1');
  await t.depto('esp-1', '101', piso: '1');
  await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
}
