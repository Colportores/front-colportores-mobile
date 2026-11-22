// Arnés de los tests de #649 (navegación del shell: «ir a la casa» y «tras guardar vuelve al mapa»):
// la pantalla principal entera, con la Lista, el mapa falso y la hoja de la casa, y los destinos de la
// hoja ("Registrar visita", «$ Cobrar», «+ Agendar») que cada test enchufa.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/inicio/presentation/providers/navegacion_inicio_provider.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/persona_falsos.dart';
import 'lista_ubicaciones_arnes.dart' show asentarLista;

final sesion649 = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Cómo contesta cada destino de la hoja de la casa: lo que devuelve (`true` = se guardó) o lo que
/// lanza. Cuenta cuántas veces lo llamaron y, con [espera], lo retiene hasta que el test lo suelte.
final class Destino649<T> {
  Destino649([this.resultado]);

  Object? resultado;
  Object? falla;
  Completer<void>? espera;
  final llamadas = <T>[];

  Future<Object?> llamar(T datos) async {
    llamadas.add(datos);
    final retenido = espera;
    if (retenido != null) await retenido.future;
    if (falla != null) throw falla!;
    return resultado;
  }
}

/// Todo lo que un test de #649 necesita tocar.
final class Montaje649 {
  Montaje649({
    required this.mapa,
    required this.repo,
    required this.registrar,
    required this.cobrar,
    required this.agendar,
  });

  final FabricaMapaFalsa mapa;
  final RepoListaFalso repo;
  final Destino649<ContextoDeVisita> registrar;
  final Destino649<ContextoDeCobro> cobrar;
  final Destino649<ContextoDeCita> agendar;

  late WidgetTester tester;

  ProviderContainer get contenedor =>
      ProviderScope.containerOf(tester.element(find.byType(InicioPage)), listen: false);

  NavegacionInicio get navegacion => contenedor.read(navegacionInicioProvider);

  NavegacionInicioNotifier get notificador => contenedor.read(navegacionInicioProvider.notifier);

  String? get seleccionada => contenedor.read(mapaUbicacionesProvider('col-1')).seleccionadaId;

  /// La pestaña a la vista de la barra inferior.
  int get pestana => tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> irA(String nombre) async {
    await tester.tap(find.byKey(Key('inicio_pestana_$nombre')));
    await asentarLista(tester);
  }

  Future<void> asentar() => asentarLista(tester);
}

/// La pantalla principal en la pestaña «Hoy», con [filas] en la Lista y el mapa.
Future<Montaje649> montar649(
  WidgetTester tester, {
  required List<UbicacionConResumen> filas,
  GpsFalso? gps,
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool listaSePuedeLeer = true,
  Destino649<ContextoDeVisita>? registrar,
  Destino649<ContextoDeCobro>? cobrar,
  Destino649<ContextoDeCita>? agendar,
  List<Override> extras = const [],
  Key? clave,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final montaje = Montaje649(
    mapa: FabricaMapaFalsa(),
    repo: RepoListaFalso(filas),
    registrar: registrar ?? Destino649<ContextoDeVisita>(true),
    cobrar: cobrar ?? Destino649<ContextoDeCobro>(true),
    agendar: agendar ?? Destino649<ContextoDeCita>(true),
  )..tester = tester;
  montaje.repo.fallaAlSuscribir = !listaSePuedeLeer;
  await tester.pumpWidget(
    ProviderScope(
      key: clave,
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(repo: montaje.repo, gps: gps),
        ...overridesPestanaMapa(montaje.mapa),
        // La hoja de la casa lee del canvas: Pedro Gómez, que debe $ 1.200, y una nota.
        ...overridesHojaCasa(
          personas: PersonaRepositorioFalso()..sembrar(contextoDelCanvas.personas),
          registrarVisita: montaje.registrar.llamar,
          cobrar: montaje.cobrar.llamar,
        ),
        programarEntrevistaDesdeLaCasaProvider.overrideWithValue(montaje.agendar.llamar),
        ...extras,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: InicioPage(sesion: sesion649),
      ),
    ),
  );
  await asentarLista(tester);
  return montaje;
}
