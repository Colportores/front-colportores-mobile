// QA-HU-UBI-007 «Gestionar espacios dentro de una ubicación» (#212): un grupo por cada escenario del
// issue y de la HU, contra las pantallas reales (la hoja de la ubicación, la hoja del depto, los
// clientes del depto, la hoja de la casa y el alta de persona), los casos de uso, los repositorios y
// Drift en memoria con la cola de sync. No hay repositorios falsos: lo que se prueba es lo que ve y lo
// que deja en el teléfono quien toca, no un doble.
//
// Lo que ya prueban a fondo otros archivos (los artboards de la vista 11, la matriz de tamaños y
// escalas, las guías de accesibilidad) se enlaza desde el PR: `hoja_ubicacion_test`, `hoja_depto_test`,
// `qa_vista11_espacios_211_*`. Acá van los escenarios completos de la HU, de punta a punta.
//
// El texto del issue manda salvo donde una decisión lo pisa: el depto sin número se ve «Sin número» y
// el número «PB-A» es el mismo que «pb a» (canvas 11); la nota por depto no tiene pantalla todavía
// (#290): su escenario se prueba contra los datos (ni se sube ni sale del teléfono).
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
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
import 'package:colportores_mobile/features/mapa/presentation/formato_espacios.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart' show SyncPolicy;

import '../../helpers/hoja_casa_falsos.dart' show itemDeLaHoja;
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/logger_mudo.dart';
import 'hoja_espacios_arnes.dart'
    show
        avisoFalla,
        avisoRepetido,
        botonAgregar,
        botonAgregarDepto,
        botonAgregarYCargarOtro,
        botonDarDeBaja,
        botonEditarUbicacion,
        botonGuardarDepto,
        campoNumero,
        campoPiso,
        escribir,
        filaDepto,
        habilitado,
        hojaDepto,
        hojaUbicacion;

/// Una DB que ya está «abierta»: los providers solo necesitan el `AppDatabase`.
class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase _db;

  @override
  AppDatabase? build() => _db;
}

final _t0 = DateTime.utc(2026, 10, 20, 10);
final _hoy = DateTime.utc(2026, 10, 27, 15);

/// Un UUID v7: la versión en el tercer grupo y la variante RFC en el cuarto.
final _uuidV7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Lo que la HU dice, letra por letra.
const _avisoDosPersonas =
    'Este espacio tiene 2 personas. Sus datos se conservarán pero el espacio quedará marcado como '
    'baja.';
const _avisoUnaPersona =
    'Este espacio tiene 1 persona. Sus datos se conservarán pero el espacio quedará marcado como '
    'baja.';
const _bloqueoUltimoEspacio =
    'No podés borrar el último espacio activo con personas. Agregá otro o reubicá las personas '
    'primero.';

/// Las columnas de `public.espacio` en el servidor (backend 0104): lo único que puede subir.
const _columnasDelServidor = {
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
final class _Telefono {
  _Telefono() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    personas = PersonaLocalDataSourceDrift(db, encolador: encolador);
  }

  late final AppDatabase db;
  late final EncoladorSyncEnMemoria encolador;
  late final UbicacionLocalDataSourceDrift ubicaciones;
  late final PersonaLocalDataSourceDrift personas;

  Auditoria get _auditoria => Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1');

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
      auditoria: _auditoria,
    ),
  );

  Future<void> depto(String id, String? numero, {String ubicacionId = 'ub-1', String? piso}) =>
      ubicaciones.insertarEspacio(
        EspacioModel(
          id: id,
          ubicacionId: ubicacionId,
          numeroDepto: numero,
          piso: piso,
          auditoria: _auditoria,
        ),
      );

  Future<void> persona(String id, String nombre, {required String espacioId}) => personas.registrar(
    persona: Persona(id: id, nombre: nombre, apellido: 'Gómez', auditoria: _auditoria),
    vinculo: EspacioPersona(
      id: 'ep-$id',
      espacioId: espacioId,
      personaId: id,
      auditoria: _auditoria,
    ),
  );

  Future<void> espacioDeLaCasa(String id, String ubicacionId) => db
      .into(db.espacios)
      .insert(
        EspaciosCompanion.insert(
          id: id,
          ubicacionId: ubicacionId,
          createdAt: _t0,
          updatedAt: _t0,
          createdBy: const Value('col-1'),
        ),
      );

  /// Lo sembrado no cuenta como lo que hizo la persona: la cola arranca vacía.
  void limpiarCola() => encolador.encolados.clear();

  Iterable<CambioEncolado> deptosEncolados() =>
      encolador.encolados.where((c) => c.entidad == 'espacio');
}

/// El teléfono del test en curso.
late _Telefono _tel;

AppDatabase get _db => _tel.db;

/// Deja correr lo que es de verdad asincrónico (SQLite) y los cuadros que dibujan lo que llegó.
Future<void> _drenar(WidgetTester tester, [int vueltas = 5]) async {
  for (var i = 0; i < vueltas; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Corre [accion] fuera del reloj falso de `testWidgets` (lecturas y escrituras directas a la DB).
Future<T> _real<T>(WidgetTester tester, Future<T> Function() accion) async =>
    (await tester.runAsync(accion)) as T;

/// Todas las filas de `espacio`, bajas incluidas.
Future<List<EspacioFila>> _espacios(WidgetTester tester) =>
    _real(tester, () => _db.select(_db.espacios).get());

Future<EspacioFila> _espacio(WidgetTester tester, String id) async =>
    (await _espacios(tester)).singleWhere((e) => e.id == id);

Future<List<PersonaFila>> _personasEnDb(WidgetTester tester) =>
    _real(tester, () => _db.select(_db.personas).get());

Future<List<EspacioPersonaFila>> _vinculos(WidgetTester tester) =>
    _real(tester, () => _db.select(_db.espacioPersonas).get());

/// Monta un anfitrión con un botón por cada pantalla que abre y la DB real detrás.
Future<void> _montar(
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
        dbLocalProvider.overrideWith(() => _DbFija(_db)),
        encoladorSyncProvider.overrideWithValue(_tel.encolador),
        relojEspaciosProvider.overrideWithValue(() => _hoy),
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

Future<void> _abrirHoja(WidgetTester tester) async {
  await tester.tap(find.text('abrir hoja'));
  await _drenar(tester);
}

/// Cierra la hoja de la ubicación con la ✕ y deja que baje.
Future<void> _cerrarHoja(WidgetTester tester) async {
  await tester.tap(find.byKey(ClavesHojaUbicacion.cerrar));
  await _drenar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _drenar(tester);
}

/// Un test con el teléfono armado por [sembrar] y cerrado al terminar.
void _prueba(
  String nombre,
  Future<void> Function(WidgetTester tester) cuerpo, {
  Future<void> Function(_Telefono tel)? sembrar,
}) {
  testWidgets(nombre, (tester) async {
    _tel = _Telefono();
    await tester.runAsync(() async {
      await sembrar?.call(_tel);
      _tel.limpiarCola();
    });
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(_tel.db.close);
  });
}

/// Un edificio sin espacios.
Future<void> _edificioVacio(_Telefono t) => t.ubicacion('ub-1');

/// Un edificio con 101 (dos personas) y 102 (sin personas).
Future<void> _edificioConDosDeptos(_Telefono t) async {
  await t.ubicacion('ub-1');
  await t.depto('esp-1', '101', piso: '1');
  await t.depto('esp-2', '102', piso: '1');
  await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
  await t.persona('p-jorge', 'Jorge', espacioId: 'esp-1');
}

/// Un edificio con un único depto (101) y una persona.
Future<void> _edificioConUnDeptoConPersona(_Telefono t) async {
  await t.ubicacion('ub-1');
  await t.depto('esp-1', '101', piso: '1');
  await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
}

void main() {
  // Hay una DB por test, cerrada al final.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // ------------------------------------------------------------------------------------------
  group('Escenario «Alta de espacio en EDIFICIO»', () {
    _prueba(
      'dado un edificio sin espacios, cuando agrego «Apto 5B», se crea local con un UUID v7 y la '
      'lista de espacios lo muestra',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        expect(find.byKey(ClavesHojaUbicacion.vacio), findsOneWidget, reason: 'sin espacios');

        await _tocar(tester, botonAgregarDepto);
        await escribir(tester, campoNumero, 'Apto 5B');
        await _tocar(tester, botonAgregar);

        // La hoja del depto se fue y la lista lo muestra.
        expect(hojaDepto, findsNothing);
        expect(find.text('Depto Apto 5B'), findsOneWidget);
        expect(find.text('1 depto'), findsOneWidget);
        expect(find.byKey(ClavesHojaUbicacion.vacio), findsNothing);
        // Quedó en el teléfono con un UUID v7, en ese edificio y a nombre del colportor.
        final filas = await _espacios(tester);
        expect(filas, hasLength(1));
        expect(filas.single.numeroDepto, 'Apto 5B');
        expect(filas.single.ubicacionId, 'ub-1');
        expect(filas.single.id, matches(_uuidV7));
        expect(filas.single.createdBy, 'col-1');
        expect(filas.single.deletedAt, isNull);
        // Y sube por la cola, sin red de por medio: un insert con el mismo id.
        final subido = _tel.deptosEncolados().single;
        expect(subido.operacion, OperacionSync.insert);
        expect(subido.payload['id'], filas.single.id);
        expect(subido.payload['numero_depto'], 'Apto 5B');
        expect(tester.takeException(), isNull);
      },
      sembrar: _edificioVacio,
    );

    _prueba('el piso es opcional y, si se escribe, el depto queda en su grupo', (tester) async {
      await _montar(tester);
      await _abrirHoja(tester);

      await _tocar(tester, botonAgregarDepto);
      await escribir(tester, campoNumero, 'Apto 5B');
      await escribir(tester, campoPiso, '5');
      await _tocar(tester, botonAgregar);

      expect(find.byKey(ClavesHojaUbicacion.grupo('5')), findsOneWidget);
      expect(find.text('PISO 5'), findsOneWidget);
      expect((await _espacios(tester)).single.piso, '5');
    }, sembrar: _edificioVacio);

    _prueba(
      '«Agregar y cargar otro» guarda el primero y deja el formulario listo para el siguiente',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);

        await escribir(tester, campoNumero, 'Apto 5B');
        await _tocar(tester, botonAgregarYCargarOtro);
        expect(hojaDepto, findsOneWidget, reason: 'la hoja sigue abierta para cargar otro');
        expect(textoDelCampo(tester), isEmpty);
        await escribir(tester, campoNumero, 'Apto 6A');
        await _tocar(tester, botonAgregar);

        expect(find.text('Depto Apto 5B'), findsOneWidget);
        expect(find.text('Depto Apto 6A'), findsOneWidget);
        expect(find.text('2 deptos'), findsOneWidget);
        final ids = (await _espacios(tester)).map((e) => e.id).toSet();
        expect(ids, hasLength(2), reason: 'dos ids distintos, ambos v7');
        expect(ids.every(_uuidV7.hasMatch), isTrue);
      },
      sembrar: _edificioVacio,
    );

    _prueba(
      'un número que ya existe (aunque cambien mayúsculas, espacios o guiones) no se guarda: avisa '
      'cuál es y no deja nada de más',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);

        await escribir(tester, campoNumero, 'pb a');
        await _tocar(tester, botonAgregar);

        expect(avisoRepetido, findsOneWidget);
        expect(find.text('Ya existe el departamento PB-A en este edificio.'), findsOneWidget);
        expect(find.text('Ver depto PB-A ›'), findsOneWidget);
        expect(await _espacios(tester), hasLength(1));
        expect(_tel.deptosEncolados(), isEmpty);
        expect(habilitado(tester, botonAgregar), isTrue, reason: 'el botón no queda trabado');
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-pba', 'PB-A');
      },
    );

    _prueba(
      'doble toque en «Agregar»: un solo depto en el teléfono y un solo insert en la cola',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);
        await escribir(tester, campoNumero, 'Apto 5B');

        await tester.tap(botonAgregar);
        await tester.tap(botonAgregar);
        await _drenar(tester);

        expect(await _espacios(tester), hasLength(1));
        expect(_tel.deptosEncolados(), hasLength(1));
        expect(find.text('1 depto'), findsOneWidget);
      },
      sembrar: _edificioVacio,
    );

    _prueba(
      'falla a mitad del alta: avisa qué hacer, no queda nada guardado ni a medias, y reintentar '
      'guarda el mismo depto una vez',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);
        await escribir(tester, campoNumero, 'Apto 5B');

        _tel.encolador.fallarCon = StateError('el motor no responde');
        await _tocar(tester, botonAgregar);

        expect(avisoFalla, findsOneWidget);
        expect(find.text(TextosEspacios.noPudimosGuardar), findsOneWidget);
        expect(await _espacios(tester), isEmpty, reason: 'la transacción se revirtió');
        expect(habilitado(tester, botonAgregar), isTrue);
        expect(habilitado(tester, botonAgregarYCargarOtro), isTrue);
        expect(textoDelCampo(tester), 'Apto 5B', reason: 'no pierde lo que escribió');

        _tel.encolador.fallarCon = null;
        await _tocar(tester, botonAgregar);

        expect(hojaDepto, findsNothing);
        expect(await _espacios(tester), hasLength(1));
        expect(find.text('Depto Apto 5B'), findsOneWidget);
      },
      sembrar: _edificioVacio,
    );

    _prueba(
      'volver atrás y reentrar: la hoja se lee de nuevo y trae el depto recién agregado',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);
        await escribir(tester, campoNumero, 'Apto 5B');
        await _tocar(tester, botonAgregar);

        await _cerrarHoja(tester);
        expect(hojaUbicacion, findsNothing);
        await _abrirHoja(tester);

        expect(find.text('Depto Apto 5B'), findsOneWidget);
        expect(find.text('1 depto'), findsOneWidget);
        await _tocar(tester, botonAgregarDepto);
        expect(textoDelCampo(tester), isEmpty, reason: 'el alta nueva arranca vacía');
      },
      sembrar: _edificioVacio,
    );

    _prueba(
      'un número del largo máximo (40 caracteres) a 320 × 568 con el texto al 200 % se guarda y se '
      've entero',
      (tester) async {
        await _montar(tester, tamano: const Size(320, 568), escala: 2);
        await _abrirHoja(tester);
        await _tocar(tester, botonAgregarDepto);
        final largo = 'Torre norte, local 12 B'.padRight(40, 'x');

        await escribir(tester, campoNumero, largo);
        await _tocar(tester, botonAgregar);

        expect((await _espacios(tester)).single.numeroDepto, largo);
        expect(find.textContaining('Torre norte'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sembrar: _edificioVacio,
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Escenario «Baja de espacio con personas»', () {
    _prueba(
      'dado un depto con 2 personas, cuando intento darlo de baja, la UI advierte con el texto de '
      'la HU y, al confirmar, procede: las personas se conservan',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        expect(hojaDepto, findsOneWidget);

        await _tocar(tester, botonDarDeBaja);

        expect(find.text(_avisoDosPersonas), findsOneWidget);
        expect(find.byKey(ClavesHojaDepto.confirmarBaja), findsOneWidget);
        // Todavía no se tocó nada.
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNull);

        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

        expect(hojaDepto, findsNothing);
        expect(filaDepto('esp-1'), findsNothing);
        expect(filaDepto('esp-2'), findsOneWidget);
        expect(find.text('1 depto'), findsOneWidget);
        final baja = await _espacio(tester, 'esp-1');
        expect(baja.deletedAt, isNotNull, reason: 'soft delete (R-UB04)');
        // Las personas siguen en el teléfono, activas y con su vínculo.
        final personas = await _personasEnDb(tester);
        expect(personas.map((p) => p.nombre), unorderedEquals(['Ana', 'Jorge']));
        expect(personas.every((p) => p.deletedAt == null), isTrue);
        final vinculos = await _vinculos(tester);
        expect(vinculos.map((v) => v.espacioId), everyElement('esp-1'));
        expect(vinculos.every((v) => v.deletedAt == null), isTrue);
        // La baja sube como un update con la fecha de baja; nada de las personas sube.
        final subido = _tel.deptosEncolados().single;
        expect(subido.operacion, OperacionSync.update);
        expect(subido.payload['id'], 'esp-1');
        expect(subido.payload['deleted_at'], isNotNull);
        expect(_tel.encolador.encolados.map((c) => c.entidad), everyElement('espacio'));
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'las personas del depto dado de baja quedan accesibles, con la etiqueta «Espacio dado de '
      'baja» y sin poder agregar más',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        await _tocar(tester, botonDarDeBaja);
        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));
        await _cerrarHoja(tester);

        await _tocar(tester, find.text('abrir clientes'));

        expect(find.textContaining('Espacio dado de baja'), findsOneWidget);
        expect(find.text(TextosPersonas.espacioDeBaja), findsOneWidget);
        expect(find.text('Ana Gómez'), findsOneWidget);
        expect(find.text('Jorge Gómez'), findsOneWidget);
        expect(find.text('+ Agregar cliente'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'si se arrepiente en el aviso, «Cancelar» no cambia nada y la hoja sigue lista para otra '
      'acción',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        await _tocar(tester, botonDarDeBaja);
        expect(find.text(_avisoDosPersonas), findsOneWidget);

        await _tocar(tester, find.byKey(ClavesHojaDepto.cancelarBaja));

        expect(find.text(_avisoDosPersonas), findsNothing);
        expect(hojaDepto, findsOneWidget);
        expect(habilitado(tester, botonDarDeBaja), isTrue);
        expect(habilitado(tester, botonGuardarDepto), isTrue);
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNull);
        expect(_tel.deptosEncolados(), isEmpty);
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'con una sola persona el aviso va en singular',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await _tocar(tester, botonDarDeBaja);

        expect(find.text(_avisoUnaPersona), findsOneWidget);
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-1', '101', piso: '1');
        await t.depto('esp-2', '102', piso: '1');
        await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
      },
    );

    _prueba(
      'doble toque en «Dar de baja» y luego en «Dar de baja» del aviso: una sola baja',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await tester.tap(botonDarDeBaja);
        await tester.tap(botonDarDeBaja);
        await _drenar(tester);
        expect(find.text(_avisoDosPersonas), findsOneWidget, reason: 'un solo aviso');
        await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
        await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja), warnIfMissed: false);
        await _drenar(tester);

        expect(_tel.deptosEncolados(), hasLength(1));
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNotNull);
        expect(tester.takeException(), isNull);
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'falla a mitad de la baja: el depto sigue activo con sus personas, el aviso dice qué hacer, '
      'el botón vuelve a estar disponible y reintentar da de baja',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        await _tocar(tester, botonDarDeBaja);

        _tel.encolador.fallarCon = StateError('el motor no responde');
        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

        expect(hojaDepto, findsOneWidget);
        expect(avisoFalla, findsOneWidget);
        expect(find.text(TextosEspacios.noPudimosDarDeBaja), findsOneWidget);
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNull);
        expect((await _personasEnDb(tester)).where((p) => p.deletedAt == null), hasLength(2));
        expect(habilitado(tester, botonDarDeBaja), isTrue);
        expect(habilitado(tester, botonGuardarDepto), isTrue);

        _tel.encolador.fallarCon = null;
        await _tocar(tester, botonDarDeBaja);
        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

        expect(hojaDepto, findsNothing);
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNotNull);
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'el aviso a 320 × 568 con el texto al 200 % se lee entero y sus botones se alcanzan',
      (tester) async {
        await _montar(tester, tamano: const Size(320, 568), escala: 2);
        await _abrirHoja(tester);
        // Con el texto al 200 % la cabecera ocupa casi toda la hoja: la fila se busca desplazando.
        await tester.dragUntilVisible(
          filaDepto('esp-1'),
          find.byType(Scrollable).last,
          const Offset(0, -80),
        );
        await _tocar(tester, filaDepto('esp-1'));
        expect(hojaDepto, findsOneWidget);
        await _tocar(tester, botonDarDeBaja);

        expect(find.text(_avisoDosPersonas), findsOneWidget);
        final dialogo = tester.getRect(find.byType(AlertDialog));
        expect(dialogo.left, greaterThanOrEqualTo(0));
        expect(dialogo.right, lessThanOrEqualTo(320));
        expect(dialogo.bottom, lessThanOrEqualTo(568));
        for (final clave in [ClavesHojaDepto.cancelarBaja, ClavesHojaDepto.confirmarBaja]) {
          await tester.ensureVisible(find.byKey(clave));
          await tester.pump();
          expect(tester.getRect(find.byKey(clave)).bottom, lessThanOrEqualTo(568));
        }
        expect(tester.takeException(), isNull);
      },
      sembrar: _edificioConDosDeptos,
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Escenario «CASA: espacios ocultos»', () {
    Future<void> sembrarCasa(_Telefono t) async {
      await t.ubicacion('ub-casa', tipo: TipoUbicacion.casa, calle: 'Grecia', numero: '3310');
      // El espacio único de la casa no se crea con el alta de un depto (eso se rechaza): lo trae el
      // alta de la casa, por eso se siembra directo en la tabla.
      await t.espacioDeLaCasa('esp-casa', 'ub-casa');
    }

    _prueba(
      'dada una casa recién creada, cuando abro su detalle, la UI no muestra la sección «Espacios» '
      'ni deja agregar deptos',
      (tester) async {
        await _montar(tester, ubicacionId: 'ub-casa');
        await _abrirHoja(tester);

        expect(hojaUbicacion, findsOneWidget);
        expect(find.text('Grecia 3310'), findsOneWidget);
        expect(botonAgregarDepto, findsNothing);
        expect(find.textContaining('depto'), findsNothing);
        expect(find.textContaining('Depto'), findsNothing);
        expect(find.textContaining('Espacio'), findsNothing);
        expect(find.byKey(ClavesHojaUbicacion.vacio), findsNothing);
        expect(find.text('Editar casa'), findsOneWidget);
        expect(botonEditarUbicacion, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sembrar: sembrarCasa,
    );

    _prueba(
      'la hoja de la casa no muestra espacios y «+ Agregar persona» va directo al alta de persona '
      'en el espacio único',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              dbLocalProvider.overrideWith(() => _DbFija(_db)),
              encoladorSyncProvider.overrideWithValue(_tel.encolador),
            ],
            child: MaterialApp(
              theme: temaClaro(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: HojaCasa(
                    item: itemDeLaHoja(id: 'ub-casa'),
                    ahora: ahoraLista,
                    alCerrar: () {},
                    arriba: true,
                    colportorId: 'col-1',
                  ),
                ),
              ),
            ),
          ),
        );
        await _drenar(tester);

        expect(find.textContaining('Espacio'), findsNothing);
        expect(find.textContaining('Depto'), findsNothing);
        final agregar = find.byKey(ClavesHojaCasa.agregarPersona);
        expect(agregar, findsOneWidget);

        await _tocar(tester, agregar);
        await tester.enterText(
          find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Obligatorio'),
          'Jorge',
        );
        await tester.pump();
        await _tocar(tester, find.widgetWithText(FilledButton, 'Guardar persona'));

        final personas = await _personasEnDb(tester);
        expect(personas.map((p) => p.nombre), ['Jorge']);
        final vinculos = await _vinculos(tester);
        expect(vinculos.single.espacioId, 'esp-casa');
        expect(find.text('Guardamos a Jorge en este teléfono.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      sembrar: sembrarCasa,
    );

    _prueba(
      'a una casa no se le agregan deptos, ni siquiera por debajo de la pantalla',
      (tester) async {
        final contenedor = ProviderContainer(
          overrides: [
            dbLocalProvider.overrideWith(() => _DbFija(_db)),
            encoladorSyncProvider.overrideWithValue(_tel.encolador),
          ],
        );
        addTearDown(contenedor.dispose);

        final repo = contenedor.read(espacioRepositoryProvider);
        final espacio = EspacioModel(
          id: 'esp-nuevo',
          ubicacionId: 'ub-casa',
          numeroDepto: '5B',
          auditoria: Auditoria(createdAt: _hoy, updatedAt: _hoy, createdBy: 'col-1'),
        ).toEntity();
        final r = await _real(tester, () => repo.agregar(espacio));

        expect(r.isLeft(), isTrue);
        expect(await _espacios(tester), hasLength(1), reason: 'solo el espacio único de la casa');
      },
      sembrar: sembrarCasa,
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Escenario «Edge: único espacio activo con personas»', () {
    _prueba(
      'dado un edificio con 1 espacio activo con personas, cuando intento darlo de baja sin agregar '
      'otro, la UI lo bloquea con el texto de la HU y no cambia nada',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await _tocar(tester, botonDarDeBaja);

        expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsOneWidget);
        expect(find.text(_bloqueoUltimoEspacio), findsOneWidget);
        expect(
          find.text(_avisoUnaPersona),
          findsNothing,
          reason: 'no pide confirmar algo imposible',
        );
        await _tocar(tester, find.text('Entendido'));

        expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsNothing);
        expect(hojaDepto, findsOneWidget);
        expect(habilitado(tester, botonDarDeBaja), isTrue, reason: 'nada quedó trabado');
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNull);
        expect((await _personasEnDb(tester)).single.deletedAt, isNull);
        expect(_tel.deptosEncolados(), isEmpty);
      },
      sembrar: _edificioConUnDeptoConPersona,
    );

    _prueba('agregando otro espacio primero, la baja del primero ya procede (con el aviso de las '
        'personas)', (tester) async {
      await _montar(tester);
      await _abrirHoja(tester);
      await _tocar(tester, filaDepto('esp-1'));
      await _tocar(tester, botonDarDeBaja);
      await _tocar(tester, find.text('Entendido'));
      await tester.binding.handlePopRoute();
      await _drenar(tester);
      expect(hojaDepto, findsNothing);

      await _tocar(tester, botonAgregarDepto);
      await escribir(tester, campoNumero, '102');
      await _tocar(tester, botonAgregar);
      expect(find.text('2 deptos'), findsOneWidget);

      await _tocar(tester, filaDepto('esp-1'));
      await _tocar(tester, botonDarDeBaja);
      expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsNothing);
      expect(find.text(_avisoUnaPersona), findsOneWidget);
      await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

      expect((await _espacio(tester, 'esp-1')).deletedAt, isNotNull);
      expect(filaDepto('esp-1'), findsNothing);
      expect(find.text('1 depto'), findsOneWidget);
      expect((await _personasEnDb(tester)).single.deletedAt, isNull);
    }, sembrar: _edificioConUnDeptoConPersona);

    _prueba(
      'el único espacio activo SIN personas sí se puede dar de baja (la regla de «mínimo 1» solo '
      'protege a las personas) y la lista vuelve a quedar vacía',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await _tocar(tester, botonDarDeBaja);
        expect(find.text('¿Dar de baja el depto 101?'), findsOneWidget);
        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

        expect(find.byKey(ClavesHojaUbicacion.vacio), findsOneWidget);
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNotNull);
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-1', '101', piso: '1');
      },
    );

    _prueba(
      'un negocio se comporta igual que un edificio con su único espacio con personas',
      (tester) async {
        await _montar(tester, ubicacionId: 'ub-neg');
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await _tocar(tester, botonDarDeBaja);

        expect(find.text(_bloqueoUltimoEspacio), findsOneWidget);
        expect((await _espacio(tester, 'esp-1')).deletedAt, isNull);
      },
      sembrar: (t) async {
        await t.ubicacion('ub-neg', tipo: TipoUbicacion.negocio, calle: 'Grecia', numero: '3312');
        await t.depto('esp-1', 'Local 1', ubicacionId: 'ub-neg');
        await t.persona('p-ana', 'Ana', espacioId: 'esp-1');
      },
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Escenario «Borde: editar numero_depto con personas y notas del depto»', () {
    _prueba(
      'editar el número de un espacio con personas es válido: es solo una etiqueta, las personas no '
      'se tocan',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        expect(textoDelCampo(tester), '101');

        await escribir(tester, campoNumero, '301');
        await escribir(tester, campoPiso, '3');
        await _tocar(tester, botonGuardarDepto);

        expect(hojaDepto, findsNothing);
        expect(find.text('Depto 301'), findsOneWidget);
        expect(find.text('Depto 101'), findsNothing);
        expect(find.byKey(ClavesHojaUbicacion.grupo('3')), findsOneWidget);
        final editado = await _espacio(tester, 'esp-1');
        expect((editado.numeroDepto, editado.piso, editado.deletedAt), ('301', '3', null));
        expect(editado.id, 'esp-1', reason: 'es el mismo espacio, no uno nuevo');
        // Las personas y su vínculo siguen donde estaban.
        expect(
          (await _personasEnDb(tester)).map((p) => p.nombre),
          unorderedEquals(['Ana', 'Jorge']),
        );
        expect((await _vinculos(tester)).map((v) => v.espacioId), everyElement('esp-1'));
        // Lo que sube es un update con exactamente las columnas del servidor.
        final subido = _tel.deptosEncolados().single;
        expect(subido.operacion, OperacionSync.update);
        expect(subido.payload.keys.toSet(), _columnasDelServidor);
        expect((subido.payload['numero_depto'], subido.payload['piso']), ('301', '3'));
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'editar a un número que ya tiene otro depto activo avisa y no cambia nada; el mismo número '
      'con otra forma («1-0-1») no choca consigo mismo',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));

        await escribir(tester, campoNumero, '102');
        await _tocar(tester, botonGuardarDepto);
        expect(avisoRepetido, findsOneWidget);
        expect((await _espacio(tester, 'esp-1')).numeroDepto, '101');
        expect(_tel.deptosEncolados(), isEmpty);

        await escribir(tester, campoNumero, '1-0-1');
        await _tocar(tester, botonGuardarDepto);
        expect(hojaDepto, findsNothing);
        expect((await _espacio(tester, 'esp-1')).numeroDepto, '1-0-1');
      },
      sembrar: _edificioConDosDeptos,
    );

    _prueba(
      'del depto solo suben su número y su piso: la nota de un depto (target ESPACIO) es local, no '
      'encola nada y no viaja en ningún push del espacio',
      (tester) async {
        const nota = 'timbre roto, tocar fuerte';
        // La nota por depto todavía no tiene pantalla (#290, S7): se escribe la fila `nota` tal como
        // la guardará esa pantalla, en el teléfono.
        await _real(
          tester,
          () => _db
              .into(_db.notas)
              .insert(
                NotasCompanion.insert(
                  id: 'nota-1',
                  targetType: 'ESPACIO',
                  targetId: 'esp-1',
                  texto: nota,
                  createdAt: _hoy,
                  updatedAt: _hoy,
                  createdBy: const Value('col-1'),
                ),
              ),
        );
        expect(_tel.encolador.encolados, isEmpty, reason: 'guardar la nota no sube nada');
        expect(
          specsDeLaApp.singleWhere((s) => s.entity == 'nota').policy,
          SyncPolicy.local,
          reason: 'la tabla nota no sale del teléfono por sync',
        );

        // Se edita y se da de baja el depto con la nota puesta: nunca aparece en la cola.
        await _montar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, filaDepto('esp-1'));
        await escribir(tester, campoNumero, '301');
        await _tocar(tester, botonGuardarDepto);
        await _tocar(tester, filaDepto('esp-1'));
        await _tocar(tester, botonDarDeBaja);
        await _tocar(tester, find.byKey(ClavesHojaDepto.confirmarBaja));

        expect(_tel.encolador.encolados, hasLength(2));
        for (final c in _tel.encolador.encolados) {
          expect(c.entidad, 'espacio');
          expect(c.payload.keys.toSet(), _columnasDelServidor);
          expect('${c.payload}', isNot(contains(nota)));
          expect(c.payload.keys, isNot(contains('notas_espacio')));
          expect(c.payload.keys, isNot(contains('descripcion')));
        }
        final guardada = await _real(tester, () => _db.select(_db.notas).get());
        expect(guardada.single.texto, nota, reason: 'la nota sigue en el teléfono');
        expect(guardada.single.deletedAt, isNull);
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-1', '101', piso: '1');
        await t.depto('esp-2', '102', piso: '1');
      },
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Escenario «Edge: espacio sin número tras “Unir tipos”»', () {
    _prueba(
      'el espacio de la casa que se unió se ve como «Sin número» en «Sin piso», sigue con numero_depto '
      'nulo y conserva a sus personas; “Editar” le pone número',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);

        expect(find.text('Sin número'), findsOneWidget);
        expect(find.byKey(ClavesHojaUbicacion.grupo(null)), findsOneWidget);
        expect(find.text('SIN PISO'), findsOneWidget);
        expect(find.textContaining('Sin número ('), findsNothing);
        expect((await _espacio(tester, 'esp-casa')).numeroDepto, isNull);
        expect((await _personasEnDb(tester)).single.nombre, 'Ana');

        await _tocar(tester, filaDepto('esp-casa'));
        await escribir(tester, campoNumero, '3A');
        await _tocar(tester, botonGuardarDepto);

        expect(find.text('Depto 3A'), findsOneWidget);
        expect(find.text('Sin número'), findsNothing);
        expect((await _espacio(tester, 'esp-casa')).numeroDepto, '3A');
        expect((await _vinculos(tester)).single.espacioId, 'esp-casa');
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-101', '101', piso: '1');
        await t.depto('esp-casa', null);
        await t.persona('p-ana', 'Ana', espacioId: 'esp-casa');
      },
    );
  });

  group('Escenario «Edge: dos espacios sin número en el mismo edificio»', () {
    _prueba(
      'se ven los dos como «Sin número», en el orden en que se dieron de alta, sin contador y sin '
      'fundirse; numerar uno no toca al otro',
      (tester) async {
        await _montar(tester);
        await _abrirHoja(tester);

        expect(find.text('Sin número'), findsNWidgets(2));
        expect(find.textContaining('Sin número ('), findsNothing);
        expect(find.text('2 deptos'), findsOneWidget);
        // El orden de alta: la primera casa que se unió va arriba.
        final primera = tester.getTopLeft(filaDepto('esp-casa-1')).dy;
        final segunda = tester.getTopLeft(filaDepto('esp-casa-2')).dy;
        expect(primera, lessThan(segunda));
        for (final e in await _espacios(tester)) {
          expect(e.numeroDepto, isNull, reason: '${e.id}: «Sin número» es solo para mostrar');
        }

        await _tocar(tester, filaDepto('esp-casa-2'));
        await escribir(tester, campoNumero, '4C');
        await _tocar(tester, botonGuardarDepto);

        expect(find.text('Depto 4C'), findsOneWidget);
        expect(find.text('Sin número'), findsOneWidget);
        expect((await _espacio(tester, 'esp-casa-1')).numeroDepto, isNull);
        expect((await _espacio(tester, 'esp-casa-2')).numeroDepto, '4C');
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        await t.depto('esp-casa-1', null);
        await t.depto('esp-casa-2', null);
        // El orden de alta lo da `created_at`: la segunda se dio de alta después.
        await t.db.customStatement(
          "UPDATE espacio SET created_at = created_at + 60000 WHERE id = 'esp-casa-2'",
        );
      },
    );
  });

  // ------------------------------------------------------------------------------------------
  group('Datos límite de la lista de espacios', () {
    _prueba(
      '120 deptos en 6 pisos: la cuenta dice 120 y un depto lejano se encuentra y se edita',
      (tester) async {
        await _montar(tester, tamano: const Size(390, 1400));
        await _abrirHoja(tester);

        expect(find.text('120 deptos'), findsOneWidget);
        await tester.dragUntilVisible(
          filaDepto('esp-119'),
          find.byType(Scrollable).last,
          const Offset(0, -300),
        );
        await _drenar(tester, 2);
        expect(filaDepto('esp-119'), findsOneWidget);
        await _tocar(tester, filaDepto('esp-119'));
        expect(hojaDepto, findsOneWidget);
        expect(textoDelCampo(tester), '620');
        expect(tester.takeException(), isNull);
      },
      sembrar: (t) async {
        await t.ubicacion('ub-1');
        for (var i = 0; i < 120; i++) {
          await t.depto('esp-$i', '${(i ~/ 20 + 1) * 100 + i % 20 + 1}', piso: '${i ~/ 20 + 1}');
        }
      },
    );
  });
}

/// Lo que hay escrito en el campo del número.
String textoDelCampo(WidgetTester tester) => tester.widget<TextField>(campoNumero).controller!.text;
