// Arnés del QA de la vista 31 «Devolución» (HU-VEN-004, #161, PR #589): monta la pantalla real con el
// tema de la app (`temaClaro`) y un repositorio falso, y lleva la pantalla a cada estado del canvas
// (31-01 a 31-10) y a los que el canvas no dibuja. Las capturas van a `.dart_tool/qa_capturas/` con
// `--dart-define=QA_CAPTURAS=true` (nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/devolucion_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/devolucion_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/devolucion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show AgendaRepositorioQueAgenda, casaMataojo, mariaFernandez;
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'venta_ui_falsos.dart';

const conCapturas161 = bool.fromEnvironment('QA_CAPTURAS');
const conHallazgos161 = bool.fromEnvironment('QA_HALLAZGOS');

/// `false` solo para las guías de contraste de Flutter (con las fuentes reales dan falsos negativos).
bool usarFuentesReales161 = true;
bool _fuentesCargadas = false;

Future<void> cargarFuentes161(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales161) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

const chico161 = Size(360, 640);
const grande161 = Size(412, 915);

final fechaDeLaVenta161 = DateTime.utc(2026, 10, 13, 18, 20);
final ahora161 = fechaDeLaVenta161.add(const Duration(hours: 24));

RenglonDeLaVenta renglon161(
  String id,
  String titulo, {
  int cantidad = 1,
  int precio = 100000,
  int devueltas = 0,
}) => RenglonDeLaVenta(
  ventaItemId: 'i-$id',
  titulo: titulo,
  productoId: 'p-$id',
  cantidad: cantidad,
  precioUnitarioCentavos: precio,
  unidadesDevueltas: devueltas,
);

/// La venta del canvas 31: «Salud y Hogar» $ 2.600 y «Nuestros Hijos» $ 1.900, $ 4.500 en total.
VentaParaDevolver ventaCanvas161({
  int cobrado = 450000,
  int salud = 0,
  int hijos = 0,
  List<RenglonDeLaVenta>? renglones,
  DateTime? fecha,
}) {
  final lista =
      renglones ??
      [
        renglon161('salud', 'Salud y Hogar', precio: 260000, devueltas: salud),
        renglon161('hijos', 'Nuestros Hijos', precio: 190000, devueltas: hijos),
      ];
  return VentaParaDevolver(
    ventaId: 'v-1',
    numeroTalonario: '0042',
    fecha: fecha ?? fechaDeLaVenta161,
    montoTotalCentavos: lista.fold(0, (s, r) => s + r.cantidad * r.precioUnitarioCentavos),
    cobradoCentavos: cobrado,
    reembolsadoCentavos: 0,
    renglones: lista,
  );
}

class RepoFalso161 implements DevolucionRepository {
  RepoFalso161(this.venta);

  VentaParaDevolver? venta;
  Failure? fallaAlLeer;

  /// Las respuestas de [registrar], en orden; cuando se acaban, se registra bien.
  final respuestas = <Future<Either<Failure, DevolucionRegistrada>> Function()>[];
  final pedidos = <PedidoDeDevolucion>[];
  var lecturas = 0;
  Completer<void>? lecturaDetenida;

  @override
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId) async {
    lecturas++;
    await lecturaDetenida?.future;
    final falla = fallaAlLeer;
    return falla != null ? Left(falla) : Right(venta);
  }

  @override
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido) async {
    pedidos.add(pedido);
    if (respuestas.isNotEmpty) return respuestas.removeAt(0)();
    return Right(registrada(pedido));
  }

  DevolucionRegistrada registrada(PedidoDeDevolucion pedido) {
    final v = venta!;
    final cuenta = ReglasDeDevolucion.cuenta(v, pedido.unidadesPorRenglon);
    final debo = pedido.queHacer == QueHacerConLaDiferencia.devolverDespues
        ? cuenta.pagoDeMasCentavos
        : 0;
    return DevolucionRegistrada(
      devolucion: Devolucion(
        id: pedido.id,
        ventaId: pedido.ventaId,
        productos: const [],
        fechaDevolucion: pedido.ahora,
        auditoria: auditoriaPersonas(),
      ),
      totalCentavos: cuenta.seQuedaConCentavos,
      saldoCentavos: cuenta.saldoNuevoCentavos,
      deboAlClienteCentavos: debo,
      eraTotal: cuenta.esTotal,
    );
  }
}

class Montaje161 {
  Montaje161(this.repo, this.ids, this.resultados);
  final RepoFalso161 repo;
  final List<String> ids;
  final List<bool?> resultados;
}

Future<Montaje161> montar161(
  WidgetTester tester,
  RepoFalso161 repo, {
  DateTime? ahora,
  double escala = 1,
  Size tamano = chico161,
  String? personaId = 'per-1',
  bool asentarLaLectura = true,
  List<Override> extra = const [],
}) async {
  await cargarFuentes161(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ids = <String>[];
  final resultados = <bool?>[];
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      // ignore: always_specify_types
      overrides: [
        ...extra,
        devolucionRepositoryProvider.overrideWithValue(repo),
        generadorIdDevolucionProvider.overrideWithValue(() {
          final id = 'd-${++n}';
          ids.add(id);
          return id;
        }),
        relojDevolucionProvider.overrideWithValue(() => ahora ?? ahora161),
        personasDelEspacioProvider.overrideWith(
          (ref, espacioId) =>
              Stream.value([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]),
        ),
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
              child: TextButton(
                key: const Key('abrir'),
                onPressed: () async {
                  final r = await DevolucionPage.abrir(
                    context,
                    ventaId: 'v-1',
                    colportorId: 'col-1',
                    espacioId: 'esp-1',
                    personaId: personaId,
                  );
                  resultados.add(r);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  if (asentarLaLectura) await asentar(tester);
  return Montaje161(repo, ids, resultados);
}

Finder mas161(String titulo) => find.byTooltip('Uno más de $titulo');
Finder menos161(String titulo) => find.byTooltip('Uno menos de $titulo');
Finder get cta161 => find.byKey(const Key('venta_cta'));
Finder get motivo161 => find.descendant(
  of: find.byKey(const Key('devolucion_motivo')),
  matching: find.byType(TextField),
);

FilledButton boton161(WidgetTester tester) => tester.widget<FilledButton>(cta161);

Future<void> alPrincipio161(WidgetTester tester) async {
  final lista = find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable));
  tester.state<ScrollableState>(lista.first).position.jumpTo(0);
  await tester.pump();
}

Future<void> confirmarEnLaHoja161(WidgetTester tester) async {
  await tocar(tester, cta161);
  await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
}

/// Los estados que se miran. Los `a3x` son los artboards del canvas; el resto, los que el canvas no
/// dibuja pero la HU o las reglas del proyecto piden.
enum Estado161 {
  a01Elegir('31-01 elegir qué devuelve'),
  a09NadaElegido('31-09 nada elegido'),
  a02PagoDeMas('31-02 pagó de más, sin elegir'),
  a03SeLoDevuelvoAhora('31-03 se lo devuelvo ahora'),
  a04HojaConfirmar('31-04 hoja de confirmar'),
  a05Registrada('31-05 registrada con deuda'),
  a05bRegistradaSinDeuda('31-05b registrada sin deuda'),
  a06ConSaldo('31-06 debía más'),
  a07Total('31-07 devolución total'),
  a08FueraDePlazo('31-08 fuera de plazo'),
  a10ErrorAlGuardar('31-10 error al guardar'),
  cargando('cargando la venta'),
  registrando('registrando'),
  ausente('venta ausente'),
  errorDeLectura('error de lectura'),
  yaDevuelta('ya devuelta por completo'),
  motivoLargo('motivo de 500 caracteres');

  const Estado161(this.titulo);
  final String titulo;
}

Future<Montaje161> llegar161(
  WidgetTester tester,
  Estado161 estado, {
  Size tamano = chico161,
  double escala = 1,
}) async {
  Future<Montaje161> con(RepoFalso161 repo, {bool asentar = true}) =>
      montar161(tester, repo, tamano: tamano, escala: escala, asentarLaLectura: asentar);

  Future<void> elegir(Montaje161 m, String titulo) async {
    await tocar(tester, mas161(titulo));
  }

  switch (estado) {
    case Estado161.a01Elegir:
      final m = await con(RepoFalso161(ventaCanvas161()));
      await elegir(m, 'Nuestros Hijos');
      return m;
    case Estado161.a09NadaElegido:
      return con(RepoFalso161(ventaCanvas161()));
    case Estado161.a02PagoDeMas:
      final m = await con(RepoFalso161(ventaCanvas161()));
      await elegir(m, 'Nuestros Hijos');
      await tocar(tester, cta161);
      return m;
    case Estado161.a03SeLoDevuelvoAhora:
      final m = await llegar161(tester, Estado161.a02PagoDeMas, tamano: tamano, escala: escala);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));
      return m;
    case Estado161.a04HojaConfirmar:
      final m = await llegar161(tester, Estado161.a02PagoDeMas, tamano: tamano, escala: escala);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverDespues')));
      await tocar(tester, cta161);
      return m;
    case Estado161.a05Registrada:
      final m = await llegar161(tester, Estado161.a02PagoDeMas, tamano: tamano, escala: escala);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverDespues')));
      await confirmarEnLaHoja161(tester);
      return m;
    case Estado161.a05bRegistradaSinDeuda:
      final m = await llegar161(tester, Estado161.a02PagoDeMas, tamano: tamano, escala: escala);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await confirmarEnLaHoja161(tester);
      return m;
    case Estado161.a06ConSaldo:
      final m = await con(RepoFalso161(ventaCanvas161(cobrado: 100000)));
      await elegir(m, 'Nuestros Hijos');
      await tocar(tester, cta161);
      return m;
    case Estado161.a07Total:
      final m = await con(RepoFalso161(ventaCanvas161()));
      await elegir(m, 'Salud y Hogar');
      await elegir(m, 'Nuestros Hijos');
      await tocar(tester, cta161);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));
      return m;
    case Estado161.a08FueraDePlazo:
      return montar161(
        tester,
        RepoFalso161(ventaCanvas161()),
        tamano: tamano,
        escala: escala,
        ahora: fechaDeLaVenta161.add(const Duration(hours: 73)),
      );
    case Estado161.a10ErrorAlGuardar:
      final repo = RepoFalso161(ventaCanvas161());
      repo.respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'prueba')));
      final m = await con(repo);
      await elegir(m, 'Nuestros Hijos');
      await tocar(tester, cta161);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await confirmarEnLaHoja161(tester);
      return m;
    case Estado161.cargando:
      final repo = RepoFalso161(ventaCanvas161())..lecturaDetenida = Completer<void>();
      final m = await con(repo, asentar: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return m;
    case Estado161.registrando:
      final repo = RepoFalso161(ventaCanvas161());
      final compuerta = Completer<Either<Failure, DevolucionRegistrada>>();
      repo.respuestas.add(() => compuerta.future);
      final m = await con(repo);
      await elegir(m, 'Nuestros Hijos');
      await tocar(tester, cta161);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await confirmarEnLaHoja161(tester);
      addTearDown(() {
        if (!compuerta.isCompleted) {
          compuerta.complete(const Left(FailureDevolucionNoGuardada()));
        }
      });
      return m;
    case Estado161.ausente:
      return con(RepoFalso161(null));
    case Estado161.errorDeLectura:
      return con(
        RepoFalso161(ventaCanvas161())..fallaAlLeer = const FailureDevolucionNoDisponible(),
      );
    case Estado161.yaDevuelta:
      return con(RepoFalso161(ventaCanvas161(salud: 1, hijos: 1)));
    case Estado161.motivoLargo:
      final m = await llegar161(tester, Estado161.a02PagoDeMas, tamano: tamano, escala: escala);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await escribir(tester, motivo161, 'Quiso cambiar el libro por otro más barato. ' * 14);
      return m;
  }
}

/// Una captura PNG de toda la pantalla (con las hojas modales encima) en `.dart_tool/qa_capturas/`.
Future<void> capturar161(WidgetTester tester, String nombre) async {
  if (!conCapturas161) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/161_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado161(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Lo que necesita «Agendar la devolución del dinero» (la pantalla de agendar del canvas 23A) para abrirse.
List<Override> agendarOverrides161() {
  final telefono = Telefono(estado: EstadoSistemaNotificaciones.activadas)
    ..recordatorios.permisoConcedido = true;
  var n = 0;
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  return [
    agendaRepositoryProvider.overrideWithValue(AgendaRepositorioQueAgenda()),
    generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
    relojVisitaProvider.overrideWithValue(() => DateTime(2026, 10, 23, 14, 35)),
    ...telefono.overrides,
    personaRepositoryProvider.overrideWithValue(personas),
    espacioRepositoryProvider.overrideWithValue(
      EspacioRepositorioParaPersonas(casaMataojo(), falla: null),
    ),
  ];
}
