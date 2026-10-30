// «Bajá el mapa de tu zona» (vista 35, artboard 35-10, HU-SYNC-010 + HU-CAM-006, #132): la hoja que
// sale en la pantalla principal cuando el pull trae una zona nueva, el teléfono está con Wi-Fi y le
// alcanza el lugar. Una vez por zona y por sesión.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/fuente_lugar_de_trabajo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/presentation/providers/mapas_offline_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../helpers/mapa_descargas_arnes.dart';
import '../helpers/tiles_falsos.dart';

final _ahora = DateTime(2026, 10, 9, 9, 30);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

final class _FuenteFalsa implements FuenteLugarDeTrabajo {
  _FuenteFalsa(this.resultado);

  Either<Failure, LugarDeTrabajo> resultado;

  @override
  Future<Either<Failure, LugarDeTrabajo>> leer() async => resultado;
}

const _lugar = LugarDeTrabajo(
  ambito: AmbitoTrabajo(zonaId: 'z-norte', ciudadId: 'c-1', departamentoId: 'd-1'),
  zonaNombre: 'Cerro Norte',
  ciudadNombre: 'Montevideo',
);

const _inscripcion = InscripcionConZona(
  id: 'insc-1',
  campaniaId: 'camp-1',
  campaniaNombre: 'Campaña Primavera 2026',
  zonaId: 'z-norte',
  zonaNombre: 'Cerro Norte',
);

final _bytesZona = bytesDePrueba(3000, semilla: 9);
final _zona = paqueteDe(_bytesZona, id: 'zona-cerro-norte', ambitoId: 'z-norte');
final _bytesCiudad = bytesDePrueba(4000, semilla: 3);
final _ciudad = paqueteDe(
  _bytesCiudad,
  id: 'ciudad-montevideo',
  nivel: NivelCobertura.ciudad,
  ambitoId: 'c-1',
);

final class _Telefono {
  _Telefono({
    TipoConexion conexion = TipoConexion.wifi,
    List<PaqueteTiles>? catalogo,
    Either<Failure, LugarDeTrabajo> lugar = const Right(_lugar),
    int libres = 1000 * 1000 * 1000,
  }) : arnes = ArnesMapa(
         conexion: conexion,
         catalogo: catalogo ?? [_zona, _ciudad],
         servirPaqueteMontevideo: false,
       ),
       fuente = _FuenteFalsa(lugar),
       medidor = EspacioFalso()..libres = libres {
    arnes.servidor.archivos[_zona.origen] = _bytesZona;
    arnes.servidor.archivos[_ciudad.origen] = _bytesCiudad;
  }

  final ArnesMapa arnes;
  final _FuenteFalsa fuente;
  final EspacioFalso medidor;
  final inscripciones = InscripcionesConZonaEnMemoria();
  final almacen = AlmacenSeguroEnMemoria();
}

Future<void> _montar(WidgetTester tester, _Telefono telefono, {double escala = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => unawaited(telefono.arnes.cerrar()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...telefono.arnes.overrides,
        fuenteLugarDeTrabajoProvider.overrideWithValue(telefono.fuente),
        medidorEspacioDiscoProvider.overrideWithValue(telefono.medidor),
        inscripcionesConZonaDataSourceProvider.overrideWithValue(telefono.inscripciones),
        zonasAvisadasRepositoryProvider.overrideWithValue(
          ZonasAvisadasRepositoryImpl(telefono.almacen, logger: loggerMudo()),
        ),
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        ...overridesPestanaMapa(),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await _asentar(tester);
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

final _hoja = find.byKey(const Key('sugerencia_mapa_hoja'));
final _descargar = find.byKey(const Key('sugerencia_mapa_descargar'));
final _ahoraNo = find.byKey(const Key('sugerencia_mapa_ahora_no'));

void main() {
  group('35-10 · bajá el mapa de tu zona', () {
    testWidgets('con una zona nueva, Wi-Fi y lugar, sale la hoja con el nombre y el peso', (
      tester,
    ) async {
      final telefono = _Telefono();
      telefono.inscripciones.publicar([_inscripcion]);

      await _montar(tester, telefono);

      expect(_hoja, findsOneWidget);
      expect(find.text('Bajá el mapa de tu zona'), findsOneWidget);
      expect(
        find.text(
          'Te asignaron Cerro Norte. Estás con Wi-Fi: bajá su mapa (1 MB) para usarlo sin señal.',
        ),
        findsOneWidget,
      );
      expect(find.text('Descargar'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
    });

    testWidgets('«Descargar» cierra la hoja y baja el mapa de la zona', (tester) async {
      final telefono = _Telefono();
      telefono.inscripciones.publicar([_inscripcion]);
      await _montar(tester, telefono);

      await tester.tap(_descargar);
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(telefono.arnes.repositorio.registrados.map((p) => p.id), ['zona-cerro-norte']);
    });

    testWidgets('doble toque en «Descargar» pide el mapa una sola vez', (tester) async {
      final telefono = _Telefono();
      telefono.arnes.servidor.retenerDespuesDe = 1000;
      telefono.inscripciones.publicar([_inscripcion]);
      await _montar(tester, telefono);

      await tester.tap(_descargar);
      await tester.tap(_descargar, warnIfMissed: false);
      await _asentar(tester);

      expect(telefono.arnes.servidor.pedidos, [0]);
    });

    testWidgets('«Ahora no» cierra la hoja, no baja nada y no vuelve a salir en la sesión', (
      tester,
    ) async {
      final telefono = _Telefono();
      telefono.inscripciones.publicar([_inscripcion]);
      await _montar(tester, telefono);

      await tester.tap(_ahoraNo);
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(telefono.arnes.servidor.pedidos, isEmpty);

      telefono.inscripciones.publicar([_inscripcion]);
      await _asentar(tester);
      expect(_hoja, findsNothing);
    });

    testWidgets('sin paquete de zona en el catálogo ofrece el de la ciudad', (tester) async {
      final telefono = _Telefono(catalogo: [_ciudad]);
      telefono.inscripciones.publicar([_inscripcion]);

      await _montar(tester, telefono);

      expect(find.text('Bajá el mapa de tu ciudad'), findsOneWidget);
      expect(
        find.text('Estás con Wi-Fi: bajá el mapa de Montevideo (1 MB) para usarlo sin señal.'),
        findsOneWidget,
      );
    });

    testWidgets('con datos móviles no sugiere nada: no se gastan datos sin avisar', (tester) async {
      final telefono = _Telefono(conexion: TipoConexion.datosMoviles);
      telefono.inscripciones.publicar([_inscripcion]);

      await _montar(tester, telefono);

      expect(_hoja, findsNothing);
    });

    testWidgets('sin lugar en el teléfono no sugiere nada', (tester) async {
      final telefono = _Telefono(libres: 100);
      telefono.inscripciones.publicar([_inscripcion]);

      await _montar(tester, telefono);

      expect(_hoja, findsNothing);
    });

    testWidgets('sin saber dónde trabaja (sin fuente) no sugiere nada y la pantalla funciona', (
      tester,
    ) async {
      final telefono = _Telefono(lugar: const Left(FailureLugarDeTrabajoNoDisponible()));
      telefono.inscripciones.publicar([_inscripcion]);

      await _montar(tester, telefono);

      expect(_hoja, findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin zona asignada no sugiere nada', (tester) async {
      final telefono = _Telefono();

      await _montar(tester, telefono);

      expect(_hoja, findsNothing);
    });

    testWidgets('si la descarga no puede empezar, la hoja lo dice y «Descargar» sigue habilitado', (
      tester,
    ) async {
      final telefono = _Telefono();
      telefono.inscripciones.publicar([_inscripcion]);
      await _montar(tester, telefono);
      // El teléfono se quedó sin lugar entre que salió la hoja y el toque.
      telefono.arnes.espacio.libres = 100;

      await tester.tap(_descargar);
      await _asentar(tester);

      expect(_hoja, findsOneWidget);
      expect(find.byKey(const Key('sugerencia_mapa_falla')), findsOneWidget);
      expect(tester.widget<FilledButton>(_descargar).onPressed, isNotNull);

      telefono.arnes.espacio.libres = 1000 * 1000 * 1000;
      await tester.tap(_descargar);
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(telefono.arnes.repositorio.registrados, isNotEmpty);
    });

    testWidgets('a textScaler 2.0 y en un teléfono chico la hoja no desborda', (tester) async {
      final telefono = _Telefono();
      telefono.inscripciones.publicar([_inscripcion]);
      tester.view.physicalSize = const Size(360, 640);

      await _montar(tester, telefono, escala: 2);
      tester.view.physicalSize = const Size(360, 640);
      await _asentar(tester);

      expect(_hoja, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
