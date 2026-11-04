// Arnés de los tests de QA de #568 («+ Agendar» de la pestaña Agenda, vista 23B·07 → lista de
// ubicaciones en modo selección → «¿Con quién?» → «Agendar visita» 23A·01). Monta la pantalla como en
// `InicioPage`: un `IndexedStack` con la pestaña Lista VIVA (fuera de la vista) y la pestaña Agenda
// a la vista, y el destino de `main.dart` (`FlujoAgendarDesdeLaAgenda.abrir` con la sesión).
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_agendar_desde_la_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'agendar_visita_arnes.dart';
import 'espacios_falsos.dart';
import 'lista_ubicaciones_falsos.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'qa_agenda_148_arnes.dart' show cargarFuentes, conCapturas;

export 'qa_agenda_148_arnes.dart'
    show
        cargarFuentes,
        conCapturas,
        contraste,
        escalas,
        expectSinTextoFueraDeLosCostados,
        tamanos,
        telefonoChico,
        telefonoGrande,
        usarFuentesReales,
        verHallazgos;

/// Los espacios de cada ubicación; lee la casa de «Agendar visita» siempre como «Mataojo 2044».
final class Espacios568 implements EspacioRepository {
  Espacios568(this.porUbicacion);

  final Map<String, List<Espacio>> porUbicacion;
  Failure? falla;
  Object? lanza;
  Completer<void>? compuerta;
  var listados = 0;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    listados += 1;
    await compuerta?.future;
    final roto = lanza;
    if (roto != null) throw roto;
    final f = falla;
    if (f != null) return Left(f);
    return Right(porUbicacion[ubicacionId] ?? const []);
  }

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async => Right(casaMataojo());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class Montaje568 {
  Montaje568({
    required this.agendas,
    required this.espacios,
    required this.lista,
    required this.llave,
    required this.contenedor,
  });
  final AgendaRepositorioQueAgenda agendas;
  final Espacios568 espacios;
  final RepoListaFalso lista;
  final GlobalKey<NavigatorState> llave;
  final ProviderContainer contenedor;
  var llamadas = 0;
}

final raiz568 = GlobalKey();

List<UbicacionConResumen> filasPorDefecto568() => [
  filaLista('u-1', calle: 'Mataojo', numero: '2044'),
  filaLista('u-2', calle: 'Rivera', numero: '77', hace: const Duration(hours: 3)),
];

/// La pestaña Agenda (con o sin visitas) dentro de un `IndexedStack` con la Lista viva, con el destino
/// de `main.dart`.
Future<Montaje568> montar568(
  WidgetTester tester, {
  List<UbicacionConResumen>? filas,
  String? sesion = 'col-1',
  List<PersonaDelEspacio>? personas,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<ItemAgenda> items = const [],
  bool listaViva = true,
  Map<String, List<Espacio>>? espacios,
  ThemeData? tema,
}) async {
  await cargarFuentes(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llave = GlobalKey<NavigatorState>();
  final lista = RepoListaFalso(filas ?? filasPorDefecto568());
  final repoEspacios = Espacios568(
    espacios ??
        {
          'u-1': [espacioDe('esp-1', null, ubicacionId: 'u-1')],
          'u-2': [espacioDe('esp-2', null, ubicacionId: 'u-2')],
          'u-3': [
            espacioDe('esp-3a', '1', ubicacionId: 'u-3'),
            espacioDe('esp-3b', '2', ubicacionId: 'u-3', orden: 1),
          ],
          'u-5': const [],
        },
  );
  final agendas = AgendaRepositorioQueAgenda();
  final telefono = Telefono(estado: EstadoSistemaNotificaciones.activadas)
    ..recordatorios.permisoConcedido = true;
  final repoPersonas = PersonaRepositorioFalso()..sembrar(personas ?? [mariaFernandez]);
  var n = 0;
  late Montaje568 m;
  final contenedor = ProviderContainer(
    overrides: [
      ...overridesLista(repo: lista),
      consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa(items)),
      relojAgendaProvider.overrideWithValue(ahoraDelCanvas),
      agendaRepositoryProvider.overrideWithValue(agendas),
      generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
      relojVisitaProvider.overrideWithValue(ahoraDelCanvas),
      ...telefono.overrides,
      personaRepositoryProvider.overrideWithValue(repoPersonas),
      espacioRepositoryProvider.overrideWithValue(repoEspacios),
      // Igual que en `main.dart`: «+ Agendar» del rótulo de un día futuro.
      agendarEnUnDiaDesdeLaAgendaProvider.overrideWith(
        (ref) => (dia) {
          m.llamadas += 1;
          final contexto = llave.currentContext;
          if (contexto == null) return false;
          return FlujoAgendarDesdeLaAgenda.abrir(contexto, colportorId: sesion, dia: dia);
        },
      ),
      // Igual que en `main.dart`.
      agendarDesdeLaAgendaProvider.overrideWith(
        (ref) => () {
          m.llamadas += 1;
          final contexto = llave.currentContext;
          if (contexto == null) return false;
          return FlujoAgendarDesdeLaAgenda.abrir(contexto, colportorId: sesion);
        },
      ),
    ],
  );
  addTearDown(contenedor.dispose);
  m = Montaje568(
    agendas: agendas,
    espacios: repoEspacios,
    lista: lista,
    llave: llave,
    contenedor: contenedor,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: contenedor,
      child: RepaintBoundary(
        key: raiz568,
        child: MaterialApp(
          navigatorKey: llave,
          theme: tema ?? temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: IndexedStack(
              index: listaViva ? 1 : 0,
              children: [
                if (listaViva)
                  ListaUbicacionesPage(
                    colportorId: 'col-1',
                    activa: false,
                    alAbrirUbicacion: (_, _) {},
                  ),
                const AgendaPage(colportorId: 'col-1'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await asentarAgendar(tester);
  return m;
}

/// Cada test termina desmontando la pantalla: el temporizador del minuto de la agenda se cancela.
void probar568(
  String descripcion,
  Future<void> Function(WidgetTester tester) cuerpo, {
  bool skip = false,
}) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: skip);
}

/// Una captura PNG de la pantalla entera (con las rutas y hojas modales encima) en
/// `.dart_tool/qa_capturas/568_<nombre>.png`. Solo con `QA_CAPTURAS=true`.
Future<void> capturar568(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final v = tester.view;
    final img = await capa.toImage(Offset.zero & (v.physicalSize / v.devicePixelRatio));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/568_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
