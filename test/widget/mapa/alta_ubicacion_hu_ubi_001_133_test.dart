// HU-UBI-001 «Alta de ubicación con captura GPS» (paraguas #133): los escenarios y casos borde de la
// HU recorridos de punta a punta. La pantalla «Nueva ubicación» real, el caso de uso real, el
// repositorio real y la base real (Drift en memoria); afuera solo lo que no existe en `flutter test`
// (GPS, geocodificador, vista nativa del mapa, ciudades de la campaña) y el motor de sync, cuya cola
// en memoria no sube nada.
//
// Los tests de widget con un repositorio falso (`alta_ubicacion_page_test.dart`) fijan la pantalla y
// los de datos (`ubicacion_local_data_source_drift_test.dart`) la base; este archivo fija que las dos
// mitades se entienden: lo que el colportor ve es lo que queda en el teléfono y en la cola.
//
// Fuera de alcance, con su issue: la justificación de «Crear igual» que se guarda en la auditoría
// local (#282, escenario con `skip` al final), la vista 39 (#451) y las ciudades de la campaña con
// fuente real (#274: hoy `CiudadesParaAltaSinFuente`; las propuestas y la lista «Elegí la ciudad» se
// prueban con `CiudadesFalsas` en `alta_ubicacion_page_test.dart`).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' show LogOutput, OutputEvent;
import 'package:uuid/uuid.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';

final _t0 = DateTime.utc(2026, 10, 27, 12);

/// Un UUID v7: versión 7 y variante RFC 4122.
final _uuidV7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Metros → grados de latitud.
double _grados(double metros) => metros / 111195.08;

final class _Logs extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

/// El teléfono del colportor `col-1`: la base real, la cola del sync (que no sube nada) y la pantalla
/// «Nueva ubicación» sobre el repositorio de verdad.
final class _Telefono {
  _Telefono({required this.gps, required this.geocodificador, required this.ciudades}) {
    db = AppDatabase(NativeDatabase.memory(), logger: AppLogger(output: logs));
    local = UbicacionLocalDataSourceDrift(db, encolador: cola);
    repo = UbicacionRepositoryImpl(local, logger: AppLogger(output: logs));
  }

  final GpsFalso gps;
  final GeocodificadorFalso geocodificador;
  final CiudadesFalsas ciudades;
  final cola = EncoladorSyncEnMemoria();
  final logs = _Logs();
  final mapa = FabricaMapaFalsa();
  final salidas = <SalidaAltaUbicacion?>[];
  late final AppDatabase db;
  late final UbicacionLocalDataSourceDrift local;
  late final UbicacionRepositoryImpl repo;
}

/// La pantalla que abre el alta y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaAltaUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: 'col-1')),
        child: const Text('abrir'),
      ),
    ),
  );
}

/// La base real no avanza con el reloj falso del test: se le da tiempo real y se bombea.
Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Telefono> _montar(
  WidgetTester tester, {
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = _Telefono(
    gps: gps ?? GpsFalso(),
    geocodificador:
        geocodificador ??
        GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234')),
    ciudades: ciudades ?? CiudadesFalsas(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: t.gps,
        geocodificador: t.geocodificador,
        ciudades: t.ciudades,
        repo: t.repo,
        ahora: _t0,
        mapa: t.mapa,
        // El generador de producción: UUID v7.
        generadorId: const Uuid().v7,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(t.salidas),
      ),
    ),
  );
  addTearDown(() => _cerrar(tester, t));
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
  return t;
}

/// Desmonta la pantalla (Drift deja un timer al cancelar un stream) y cierra la base.
Future<void> _cerrar(WidgetTester tester, _Telefono t) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(t.db.close);
}

Future<List<Map<String, Object?>>> _sql(WidgetTester tester, _Telefono t, String consulta) async {
  final filas = await tester.runAsync(() => t.db.customSelect(consulta).get());
  return [for (final f in filas!) f.data];
}

Future<int> _cuantas(WidgetTester tester, _Telefono t, String tabla) async =>
    (await _sql(tester, t, 'SELECT COUNT(*) AS n FROM $tabla')).single['n']! as int;

/// Una ubicación que ya estaba en el teléfono (la bajó el motor o la cargó el colportor).
Future<void> _sembrar(
  WidgetTester tester,
  _Telefono t, {
  String id = 'existente',
  String calle = 'Av. Italia',
  String numero = '1234',
  double metrosAlNorte = 12,
}) async {
  await tester.runAsync(
    () => t.local.insertar(
      UbicacionModel(
        id: id,
        tipo: TipoUbicacion.casa,
        calle: calle,
        numero: numero,
        lat: puntoItalia.lat + _grados(metrosAlNorte),
        lon: puntoItalia.lon,
        ciudadId: montevideo.id,
        auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-2'),
      ),
    ),
  );
  t.cola.encolados.clear();
}

Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _traer(tester, f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _registrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

/// Las tres acciones del aviso de posible duplicado.
void _tresAcciones() {
  expect(find.text(TextosDuplicado.reutilizar), findsOneWidget);
  expect(find.text(TextosDuplicado.crearIgual), findsOneWidget);
  expect(find.text(TextosDuplicado.cancelar), findsOneWidget);
}

/// «Crear igual» con su justificación.
Future<void> _crearIgual(WidgetTester tester, String justificacion) async {
  await _tocar(tester, find.text(TextosDuplicado.crearIgual));
  await tester.enterText(find.byType(TextField).last, justificacion);
  await tester.pump();
  await _tocar(tester, find.widgetWithText(FilledButton, TextosDuplicado.crearIgual));
}

void main() {
  group('Escenario: Alta exitosa con GPS preciso', () {
    testWidgets('dado GPS de ±6 m, cuando elijo «Casa» y «Registrar», la ubicación y su espacio '
        'quedan en el teléfono con UUID v7 y encolados sin nada de más', (tester) async {
      final t = await _montar(tester);
      expect(_habilitado(tester, _registrar), isFalse, reason: 'el tipo es obligatorio');

      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      final salida = t.salidas.single;
      expect(salida, isA<UbicacionCreada>());
      expect(find.text('abrir'), findsOneWidget, reason: 'la UI vuelve al mapa');

      final ubicaciones = await _sql(tester, t, 'SELECT * FROM ubicacion');
      expect(ubicaciones, hasLength(1));
      final u = ubicaciones.single;
      final id = (salida! as UbicacionCreada).ubicacion.id;
      expect(id, matches(_uuidV7));
      expect(u['id'], id);
      expect(u['tipo'], 'CASA');
      expect(u['calle'], 'Av. Italia');
      expect(u['numero'], '1234');
      expect(u['ciudad_id'], montevideo.id);
      expect(u['created_by'], 'col-1');
      expect(u['lat'], closeTo(puntoItalia.lat, 1e-9));
      expect(u['lon'], closeTo(puntoItalia.lon, 1e-9));
      expect(u['deleted_at'], isNull);

      final espacios = await _sql(tester, t, 'SELECT * FROM espacio');
      expect(espacios, hasLength(1), reason: 'la casa autocrea su espacio default');
      expect(espacios.single['ubicacion_id'], id);
      expect(espacios.single['numero_depto'], isNull, reason: 'el «—» es solo para mostrar');
      expect(espacios.single['id'], matches(_uuidV7));

      // La cola: la ubicación y su espacio, en ese orden, y el alta no escribió ningún color.
      expect(t.cola.encolados.map((c) => (c.entidad, c.operacion)), [
        ('ubicacion', OperacionSync.insert),
        ('espacio', OperacionSync.insert),
      ]);
      final payload = t.cola.encolados.first.payload;
      expect(payload['id'], id);
      expect(payload['tipo'], 'CASA');
      expect(payload['ciudad_id'], montevideo.id);
      expect(payload['lat'], closeTo(puntoItalia.lat, 1e-9));
      expect(payload['lon'], closeTo(puntoItalia.lon, 1e-9));
      expect(
        await _cuantas(tester, t, 'house_status'),
        0,
        reason: '«sin_visita» es la ausencia de fila',
      );
    });

    testWidgets('el log del alta lleva uuids y el origen de las coordenadas, nunca la dirección ni '
        'el punto', (tester) async {
      final t = await _montar(tester);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      final linea = t.logs.lineas.singleWhere((l) => l.contains('UBICACION_CREADA'));
      expect(linea, contains('"coords_source":"gps"'));
      expect(linea, contains((t.salidas.single! as UbicacionCreada).ubicacion.id));
      final todo = t.logs.lineas.join('\n');
      expect(todo, isNot(contains('Av. Italia')));
      expect(todo, isNot(contains('1234')));
      expect(todo, isNot(contains('-34.88761')));
    });

    testWidgets('un negocio no autocrea espacio: solo la ubicación va a la cola', (tester) async {
      final t = await _montar(tester);

      await _tocar(tester, find.text('Negocio'));
      await _tocar(tester, _registrar);

      expect(t.salidas.single, isA<UbicacionCreada>());
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(await _cuantas(tester, t, 'espacio'), 0);
      expect(t.cola.encolados.map((c) => c.entidad), ['ubicacion']);
    });
  });

  group('Escenario: Alta sin GPS - colocación manual', () {
    testWidgets('dado GPS denegado, cuando toco el mapa y completo el tipo, el alta procede igual '
        'y el origen queda «manual»', (tester) async {
      final t = await _montar(
        tester,
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      expect(_habilitado(tester, _registrar), isFalse);
      await _tocar(tester, find.text('Casa'));
      expect(_habilitado(tester, _registrar), isFalse, reason: 'falta el punto');

      const tocado = Coordenadas(lat: -34.9, lon: -56.2);
      t.mapa.tocar(tocado);
      await _asentar(tester);
      expect(find.text('Marcado a mano'), findsOneWidget);
      await _tocar(tester, _registrar);

      expect(t.salidas.single, isA<UbicacionCreada>());
      final u = (await _sql(tester, t, 'SELECT lat, lon FROM ubicacion')).single;
      expect(u['lat'], closeTo(tocado.lat, 1e-6));
      expect(u['lon'], closeTo(tocado.lon, 1e-6));
      expect(await _cuantas(tester, t, 'espacio'), 1);
      expect(
        t.logs.lineas.singleWhere((l) => l.contains('UBICACION_CREADA')),
        contains('"coords_source":"manual"'),
      );
    });

    testWidgets('dado un GPS que reporta (0, 0), se trata como sin GPS: no deja registrar', (
      tester,
    ) async {
      final t = await _montar(
        tester,
        gps: GpsFalso(Right(lecturaGps(8, punto: const Coordenadas(lat: 0, lon: 0)))),
      );
      await _tocar(tester, find.text('Casa'));

      expect(find.text('Sin GPS'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);
      expect(await _cuantas(tester, t, 'ubicacion'), 0);
    });
  });

  group('Escenario: Alta con GPS impreciso - confirmación adicional', () {
    testWidgets('dado ±85 m, cuando intento registrar, no se crea nada hasta que confirmo '
        '«Continuar»', (tester) async {
      final t = await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      expect(
        find.text('Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?'),
        findsOneWidget,
      );
      expect(_habilitado(tester, _registrar), isFalse);
      expect(await _cuantas(tester, t, 'ubicacion'), 0);

      await _tocar(tester, find.text('Continuar'));
      await _tocar(tester, _registrar);

      expect(t.salidas.single, isA<UbicacionCreada>());
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(
        t.logs.lineas.singleWhere((l) => l.contains('UBICACION_CREADA')),
        contains('"coords_source":"gps"'),
      );
    });

    testWidgets('«Ajustar manualmente» y mover el mapa: queda a mano y se guarda el punto movido', (
      tester,
    ) async {
      final t = await _montar(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, find.text('Ajustar manualmente'));
      const ajustado = Coordenadas(lat: -34.8871, lon: -56.1305);
      t.mapa.tocar(ajustado);
      await _asentar(tester);
      await _tocar(tester, _registrar);

      final u = (await _sql(tester, t, 'SELECT lat, lon FROM ubicacion')).single;
      expect(u['lat'], closeTo(ajustado.lat, 1e-6));
      expect(
        t.logs.lineas.singleWhere((l) => l.contains('UBICACION_CREADA')),
        contains('"coords_source":"manual"'),
      );
    });
  });

  group('Escenario: Posible duplicado a menos de 5 m', () {
    testWidgets('dado «Av. Italia 1230» a 3 m, cuando registro «Av. Italia 1234», no se crea la '
        'nueva y veo las 3 acciones', (tester) async {
      final t = await _montar(tester);
      await _sembrar(tester, t, numero: '1230', metrosAlNorte: 3);
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(find.textContaining('Ya existe una ubicación a'), findsOneWidget);
      _tresAcciones();
      expect(t.salidas, isEmpty);
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(await _cuantas(tester, t, 'espacio'), 0);
      expect(t.cola.encolados, isEmpty);
    });

    testWidgets('«Reutilizar esta» abre la existente: no escribe ni encola nada', (tester) async {
      final t = await _montar(tester);
      await _sembrar(tester, t, numero: '1230', metrosAlNorte: 3);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      await _tocar(tester, find.text(TextosDuplicado.reutilizar));

      expect((t.salidas.single! as UbicacionReutilizada).ubicacionId, 'existente');
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(t.cola.encolados, isEmpty);
    });

    testWidgets('«Cancelar» vuelve al alta con todo lo cargado, y se puede registrar otra vez', (
      tester,
    ) async {
      final t = await _montar(tester);
      await _sembrar(tester, t, numero: '1230', metrosAlNorte: 3);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      await _tocar(tester, find.text(TextosDuplicado.cancelar));

      expect(find.text('Nueva ubicación'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
      expect(t.salidas, isEmpty);
      expect(await _cuantas(tester, t, 'ubicacion'), 1);

      await _tocar(tester, _registrar);
      _tresAcciones();
    });

    testWidgets('«Crear igual» con la justificación crea la nueva y el texto no sale a la cola ni '
        'a los logs', (tester) async {
      final t = await _montar(tester);
      await _sembrar(tester, t, numero: '1230', metrosAlNorte: 3);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      const motivo = 'Es la puerta de al lado, tiene otro timbre';
      await _crearIgual(tester, motivo);

      expect(t.salidas.single, isA<UbicacionCreada>());
      expect(await _cuantas(tester, t, 'ubicacion'), 2);
      expect(t.cola.encolados.map((c) => c.entidad), ['ubicacion', 'espacio']);
      expect('${t.cola.encolados.map((c) => c.payload)}', isNot(contains(motivo)));
      expect(t.logs.lineas.join('\n'), isNot(contains(motivo)));
      final columnas = await _sql(tester, t, 'SELECT * FROM ubicacion');
      expect('$columnas', isNot(contains(motivo)), reason: 'no va a ninguna columna');
    });
  });

  group('Escenario: Misma dirección a menos de 100 m', () {
    testWidgets('dado «Av. Italia 1234» a 15 m, cuando registro «av.  itália  1234», no se crea y '
        'solo puedo abrir la existente', (tester) async {
      final t = await _montar(
        tester,
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'av.  itália ', numero: '1234'),
        ),
      );
      await _sembrar(tester, t, metrosAlNorte: 15);
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(find.text(TextosDuplicado.abrirExistente), findsOneWidget);
      expect(find.text(TextosDuplicado.crearIgual), findsNothing);
      expect(find.text(TextosDuplicado.reutilizar), findsNothing);
      expect(await _cuantas(tester, t, 'ubicacion'), 1);

      await _tocar(tester, find.text(TextosDuplicado.abrirExistente));

      expect((t.salidas.single! as UbicacionReutilizada).ubicacionId, 'existente');
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(t.cola.encolados, isEmpty);
    });

    testWidgets('calle con Ñ y tildes: se compara sin ellas pero se guarda como se escribió', (
      tester,
    ) async {
      final t = await _montar(
        tester,
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'AV.  NUÑEZ de Ñandú', numero: '50'),
        ),
      );
      await _sembrar(tester, t, calle: 'Av. Nunez de Nandu', numero: '50', metrosAlNorte: 20);
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(find.text(TextosDuplicado.abrirExistente), findsOneWidget);
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
    });

    testWidgets('una calle con Ñ y tildes sin duplicado se guarda tal cual, con sus caracteres', (
      tester,
    ) async {
      final t = await _montar(
        tester,
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Núñez de Ñandú', numero: '50'),
        ),
      );
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      final u = (await _sql(tester, t, 'SELECT calle, numero FROM ubicacion')).single;
      expect(u['calle'], 'Av. Núñez de Ñandú');
      expect(u['numero'], '50');
    });
  });

  group('Escenario: Misma dirección a 100 m o más', () {
    testWidgets(
      'dado «Av. Italia 1234» a 150 m, cuando registro lo mismo, avisa con las 3 acciones '
      'y con «Crear igual» quedan las dos',
      (tester) async {
        final t = await _montar(tester);
        await _sembrar(tester, t, metrosAlNorte: 150);
        await _tocar(tester, find.text('Casa'));

        await _tocar(tester, _registrar);

        _tresAcciones();
        expect(await _cuantas(tester, t, 'ubicacion'), 1);

        await _crearIgual(tester, 'Otra casa en la misma calle');

        expect(t.salidas.single, isA<UbicacionCreada>());
        expect(await _cuantas(tester, t, 'ubicacion'), 2);
        expect(await _cuantas(tester, t, 'espacio'), 1);
      },
    );
  });

  group('Escenario: «Crear igual» guarda la justificación solo en el teléfono (#282)', () {
    testWidgets(
      'dado un posible duplicado a 3 m, cuando elijo «Crear igual», la ayuda dice «Queda guardada '
      'en tu teléfono.» y el texto queda en la auditoría local con el uuid de la ubicación nueva',
      (tester) async {
        final t = await _montar(tester);
        await _sembrar(tester, t, numero: '1230', metrosAlNorte: 3);
        await _tocar(tester, find.text('Casa'));
        await _tocar(tester, _registrar);
        await _tocar(tester, find.text(TextosDuplicado.crearIgual));

        expect(find.text('Queda guardada en tu teléfono.'), findsOneWidget);

        const motivo = 'Es la puerta de al lado, tiene otro timbre';
        await tester.enterText(find.byType(TextField).last, motivo);
        await tester.pump();
        await _tocar(tester, find.widgetWithText(FilledButton, TextosDuplicado.crearIgual));

        final id = (t.salidas.single! as UbicacionCreada).ubicacion.id;
        final auditoria = await _sql(tester, t, 'SELECT evento, uuid, motivo FROM audit_log');
        final filas = auditoria.where((f) => f['uuid'] == id && f['motivo'] == motivo);
        expect(filas.map((f) => f['evento']), ['ubicacion_crear_igual']);
        // Solo local: ni la cola de sync ni ninguna columna de la ubicación llevan el texto.
        expect('${t.cola.encolados.map((c) => c.payload)}', isNot(contains(motivo)));
        expect(t.cola.encolados.map((c) => c.entidad).toSet(), {'ubicacion', 'espacio'});
        expect('${await _sql(tester, t, 'SELECT * FROM ubicacion')}', isNot(contains(motivo)));
      },
    );
  });

  group('Escenario: Offline', () {
    testWidgets(
      'dado que no hay red (ni dirección del geocodificador), cuando registro, el alta se '
      'completa local, queda PENDING en la cola y la UI no avisa nada de la red',
      (tester) async {
        final t = await _montar(tester, geocodificador: GeocodificadorFalso());
        await _tocar(tester, find.text('Negocio'));

        await _tocar(tester, _registrar);

        expect(t.salidas.single, isA<UbicacionCreada>());
        expect(await _cuantas(tester, t, 'ubicacion'), 1);
        expect(t.cola.encolados.single.entidad, 'ubicacion');
        expect(t.cola.encolados.single.operacion, OperacionSync.insert);
        expect(find.textContaining('conexión'), findsNothing);
      },
    );
  });

  group('La ciudad no limita ni se pierde en el alta', () {
    testWidgets('dado que cambio la ciudad propuesta con «Cambiar», la elegida es la que se guarda '
        'y viaja en la cola', (tester) async {
      final t = await _montar(tester);

      await _tocar(tester, find.text('detectada · Cambiar'));
      await _tocar(tester, find.text('Canelones'));
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      final u = (await _sql(tester, t, 'SELECT ciudad_id FROM ubicacion')).single;
      expect(u['ciudad_id'], canelones.id);
      expect(t.cola.encolados.first.payload['ciudad_id'], canelones.id);
    });

    testWidgets('dado una campaña sin ciudades, «Registrar» no se habilita y no se escribe nada', (
      tester,
    ) async {
      final t = await _montar(
        tester,
        ciudades: CiudadesFalsas(propone: (_) => const CampaniaSinCiudades()),
      );
      await _tocar(tester, find.text('Casa'));

      expect(find.text(TextosAlta.sinCiudades), findsOneWidget);
      expect(_habilitado(tester, _registrar), isFalse);
      expect(await _cuantas(tester, t, 'ubicacion'), 0);
      expect(t.cola.encolados, isEmpty);
    });
  });

  group('Casos borde', () {
    testWidgets('doble toque en «Registrar»: una sola ubicación, un solo espacio y una sola alta '
        'en la cola', (tester) async {
      final t = await _montar(tester);
      await _tocar(tester, find.text('Casa'));

      await _traer(tester, _registrar);
      await tester.tap(_registrar);
      await tester.tap(_registrar, warnIfMissed: false);
      await _asentar(tester);

      expect(t.salidas, hasLength(1));
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(await _cuantas(tester, t, 'espacio'), 1);
      expect(t.cola.encolados.map((c) => c.entidad), ['ubicacion', 'espacio']);
    });

    testWidgets('si el motor de sync falla a mitad del alta: no queda nada a medias, el botón '
        'vuelve y el reintento crea una sola', (tester) async {
      final t = await _montar(tester);
      await _tocar(tester, find.text('Casa'));
      t.cola.fallarCon = StateError('motor apagado');

      await _tocar(tester, _registrar);

      expect(find.text(TextosAlta.noPudimosGuardar), findsOneWidget);
      expect(_habilitado(tester, _registrar), isTrue);
      expect(find.text(TextosAlta.registrar), findsOneWidget, reason: 'sin «Registrando…» trabado');
      expect(t.salidas, isEmpty);
      expect(await _cuantas(tester, t, 'ubicacion'), 0, reason: 'la transacción se revirtió');
      expect(await _cuantas(tester, t, 'espacio'), 0);

      t.cola.fallarCon = null;
      await _tocar(tester, _registrar);

      expect(t.salidas.single, isA<UbicacionCreada>());
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
      expect(await _cuantas(tester, t, 'espacio'), 1);
    });

    testWidgets('✕ no deja nada, y al reentrar arranca de cero: cada alta es otra ubicación', (
      tester,
    ) async {
      final t = await _montar(tester);
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, find.byTooltip('Cerrar'));
      expect(t.salidas, [null]);
      expect(await _cuantas(tester, t, 'ubicacion'), 0);

      await tester.tap(find.text('abrir'));
      await _asentar(tester);
      expect(_habilitado(tester, _registrar), isFalse, reason: 'el tipo vuelve sin elegir');
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);
      final primera = (t.salidas.last! as UbicacionCreada).ubicacion.id;

      // La segunda, 400 m al norte y en otra calle: no es un duplicado de la primera.
      t.gps.respuesta = Right(
        lecturaGps(
          6,
          punto: Coordenadas(lat: puntoItalia.lat + _grados(400), lon: puntoItalia.lon),
        ),
      );
      t.geocodificador.respuesta = (_) => const DireccionDelPunto(calle: 'Bulevar', numero: '10');
      await tester.tap(find.text('abrir'));
      await _asentar(tester);
      expect(_habilitado(tester, _registrar), isFalse, reason: 'el tipo vuelve sin elegir');
      await _tocar(tester, find.text('Casa'));
      await _tocar(tester, _registrar);

      final segunda = (t.salidas.last! as UbicacionCreada).ubicacion.id;
      expect(segunda, isNot(primera));
      expect(await _cuantas(tester, t, 'ubicacion'), 2);
      expect(await _cuantas(tester, t, 'espacio'), 2);
    });

    testWidgets('texto al 200 % en 320×568: el alta completa se registra y se guarda', (
      tester,
    ) async {
      final t = await _montar(tester, escala: 2, tamano: const Size(320, 568));
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(tester.takeException(), isNull);
      expect(t.salidas.single, isA<UbicacionCreada>());
      expect(await _cuantas(tester, t, 'ubicacion'), 1);
    });

    testWidgets('calle y número larguísimos: la pantalla los corta al límite y la base guarda '
        'exactamente eso', (tester) async {
      final t = await _montar(tester, geocodificador: GeocodificadorFalso());
      await tester.ensureVisible(find.widgetWithText(TextField, 'Calle'));
      await tester.enterText(find.widgetWithText(TextField, 'Calle'), 'C' * 400);
      await tester.enterText(find.widgetWithText(TextField, 'Nº'), '9' * 100);
      await tester.pump();
      await _tocar(tester, find.text('Casa'));

      await _tocar(tester, _registrar);

      expect(tester.takeException(), isNull);
      final u = (await _sql(tester, t, 'SELECT calle, numero FROM ubicacion')).single;
      expect(u['calle'], 'C' * 120);
      expect(u['numero'], '9' * 20);
    });
  });
}
