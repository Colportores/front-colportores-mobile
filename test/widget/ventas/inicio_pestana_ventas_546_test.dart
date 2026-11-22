// La pestaña «Ventas» de la pantalla principal (HU-VEN-001, #546): «+ Registrar venta» lleva a elegir a
// la persona; «Precios» sigue donde estaba; sin personas, «Ir al mapa» cambia de pestaña.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/mapa_ubicaciones_page.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/persona_para_vender.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/elegir_persona_para_vender_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_elegir_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/personas_para_vender_falsos.dart';
import '../mapa/lista_ubicaciones_arnes.dart' show asentarLista;

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Las rutas tardan hasta 800 ms en entrar y salir: más fotogramas que `asentarLista`, sin esperar a
/// los indicadores que giran para siempre.
Future<void> _asentarRuta(WidgetTester tester) => asentarLista(tester, 25);

Future<LectorDePersonasParaVenderFalso> _montar(
  WidgetTester tester, {
  List<PersonaParaVender>? personas,
  double escala = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lector = LectorDePersonasParaVenderFalso(personas ?? [personaParaVender('1')]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 28, 15)),
        ...overridesLista(repo: RepoListaFalso(const [])),
        ...overridesPestanaMapa(FabricaMapaFalsa()),
        lectorDePersonasParaVenderProvider.overrideWithValue(lector),
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
  await asentarLista(tester);
  await tester.tap(find.byKey(const Key('inicio_pestana_ventas')));
  await asentarLista(tester);
  return lector;
}

void main() {
  testWidgets('la pestaña Ventas ofrece «+ Registrar venta» y «Precios»', (tester) async {
    await _montar(tester);

    expect(find.byKey(const Key('ventas_registrar')), findsOneWidget);
    expect(find.text(TextosElegirPersona.registrarVenta), findsOneWidget);
    expect(find.byKey(const Key('ventas_precios')), findsOneWidget);
  });

  testWidgets('«+ Registrar venta» abre la lista y «volver» deja la pestaña Ventas', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(find.byKey(const Key('ventas_registrar')));
    await _asentarRuta(tester);

    expect(find.byType(ElegirPersonaParaVenderPage), findsOneWidget);
    expect(find.text('María Fernández'), findsOneWidget);

    await tester.tap(find.byKey(const Key('venta_atras')));
    await _asentarRuta(tester);

    expect(find.byType(ElegirPersonaParaVenderPage), findsNothing);
    expect(find.byKey(const Key('ventas_registrar')), findsOneWidget);
  });

  testWidgets('dos toques seguidos en «+ Registrar venta» abren una sola lista', (tester) async {
    final lector = await _montar(tester);

    await tester.tap(find.byKey(const Key('ventas_registrar')));
    await tester.tap(find.byKey(const Key('ventas_registrar')), warnIfMissed: false);
    await _asentarRuta(tester);

    expect(find.byType(ElegirPersonaParaVenderPage), findsOneWidget);
    expect(lector.suscripciones, 1);
    await tester.tap(find.byKey(const Key('venta_atras')));
    await _asentarRuta(tester);
    expect(find.byType(ElegirPersonaParaVenderPage), findsNothing);
  });

  testWidgets('sin personas, «Ir al mapa» cierra la lista y abre la pestaña Mapa', (tester) async {
    await _montar(tester, personas: const []);

    await tester.tap(find.byKey(const Key('ventas_registrar')));
    await _asentarRuta(tester);
    await tester.tap(find.text(TextosElegirPersona.irAlMapa));
    await _asentarRuta(tester);

    expect(find.byType(ElegirPersonaParaVenderPage), findsNothing);
    expect(tester.widget<MapaUbicacionesPage>(find.byType(MapaUbicacionesPage)).activa, isTrue);
  });

  testWidgets('con letra al 200 % el botón y «Precios» se alcanzan y no hay overflow', (
    tester,
  ) async {
    await _montar(tester, escala: 2);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('ventas_registrar'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('ventas_precios'))).height,
      greaterThanOrEqualTo(48),
    );
  });
}
