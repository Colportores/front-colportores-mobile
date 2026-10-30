// Arnés de los tests de QA de la ficha de una persona (vista 32B, HU-UBI-009, #141, PR #563): lleva
// la pantalla real, a los tamaños de la matriz de QA, a cada uno de sus estados (los siete artboards
// del canvas más los que el canvas no dibuja) y saca capturas a `.dart_tool/qa_capturas/563_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/ficha_persona_arnes.dart';

export '../widget/mapa/ficha_persona_arnes.dart';

/// Los dos tamaños de la matriz de QA (móvil chico y grande).
const telefonoChico563 = Size(360, 640);
const telefonoGrande563 = Size(412, 915);

/// ¿Se cargan las fuentes reales? Los tests de las guías de contraste las apagan (con letra real el
/// `textContrastGuideline` da falsos negativos).
bool usarFuentesReales563 = true;
var _fuentesCargadas = false;

Future<void> cargarFuentes563(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales563) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        // Roboto: la letra que un Android real usa donde el texto no trae `fontFamily`.
        final roboto = FontLoader('Roboto');
        for (final peso in ['regular', 'medium', 'bold']) {
          final f = File('${dir.path}/artifacts/material_fonts/roboto-$peso.ttf');
          if (f.existsSync()) {
            roboto.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
          }
        }
        await roboto.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

/// Una captura PNG de todo lo que se ve en `.dart_tool/qa_capturas/563_<nombre>.png`. Solo con
/// `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar563(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & (vista.size));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/563_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Cada estado de la ficha.
enum EstadoFicha {
  completa('32B·01 ficha completa'),
  telefonoVisible('32B·02 teléfono a la vista'),
  personaDeBaja('32B·04 persona de baja'),
  sinHistorial('32B·05 sin historial ni teléfono'),
  cargando('32B·06 cargando'),
  error('32B·07 error al leer'),
  deptoDeBaja('32B·08 depto de baja'),
  personaNoEncontrada('persona que ya no está'),
  sinMovimientos('sin movimientos aún'),
  conEntregasYCobros('con entregas y cobros'),
  muchosMovimientos('130 movimientos con «Ver más»'),
  textosLargos('nombre, dirección, nota y líneas larguísimos'),
  reactivandoPersona('reactivando a la persona'),
  reactivandoDepto('reactivando el depto'),
  errorAlReactivar('no pudo reactivar'),
  noPudoLlamar('no pudo abrir el marcador'),
  menuAbierto('menú ⋯ abierto'),
  conLector('ficha completa con lector'),
  filtroConSaldo('32B·03 filtro «Con saldo»'),
  filtroSinResultados('32B·03 filtro sin resultados'),
  ubicacionDeBaja('depto y ubicación de baja'),
  sinDeptoActivo('sin ningún depto activo');

  const EstadoFicha(this.rotulo);

  final String rotulo;
}

/// La ficha del canvas 32B·01: María con teléfono, cuenta, dos notas, una venta y una visita.
MundoFicha mundoCompleto563() {
  final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
    ..conEdicion = true
    ..conRegistrarVisita = true;
  m.cuentas.cuenta = cuentaConSaldo;
  return m;
}

/// El historial con cobros y entregas (los de otros carriles) mezclados con la venta y la visita.
void conEntregasYCobros563(MundoFicha m) {
  m.movimientos.poner([
    CobroEnFicha(
      id: 'cob-1',
      fecha: DateTime(2026, 10, 20, 12),
      montoCentavos: 60000,
      efectivo: true,
      ventaId: 'ven-1',
      numeroTalonario: '0042',
    ),
    EntregaEnFicha(
      id: 'ent-1',
      fecha: DateTime(2026, 10, 26, 12),
      pendiente: true,
      lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
    ),
    EntregaEnFicha(
      id: 'ent-0',
      fecha: DateTime(2026, 10, 12, 12),
      pendiente: false,
      lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
    ),
  ]);
}

MundoFicha mundoDe563(EstadoFicha estado) {
  switch (estado) {
    case EstadoFicha.completa:
    case EstadoFicha.telefonoVisible:
    case EstadoFicha.menuAbierto:
    case EstadoFicha.conLector:
    case EstadoFicha.noPudoLlamar:
    case EstadoFicha.filtroConSaldo:
    case EstadoFicha.filtroSinResultados:
      return mundoCompleto563();
    case EstadoFicha.ubicacionDeBaja:
      final m = MundoFicha(
        historial: historialDelCanvas(),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoDeptoDeBaja,
        lugarInicial: (
          espacio: espacioDePersonas(numeroDepto: '3B', deletedAt: DateTime.utc(2026, 10, 20)),
          ubicacion: ubicacionDePersonas(deletedAt: DateTime.utc(2026, 10, 20)),
        ),
      )..conEdicion = true;
      m.cuentas.cuenta = cuentaConSaldo;
      return m;
    case EstadoFicha.sinDeptoActivo:
      return MundoFicha(
        historial: historialDelCanvas(),
        contexto: const ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.sinEspacioActivo,
        ),
      );
    case EstadoFicha.personaDeBaja:
    case EstadoFicha.reactivandoPersona:
    case EstadoFicha.errorAlReactivar:
      final m = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoBajaDesde22(),
      );
      m.cuentas.cuenta = cuentaConSaldo;
      m.personas.sembrar([clienteDeBajaDePersonas('per-1', 'María', apellido: 'Pérez')]);
      return m;
    case EstadoFicha.sinHistorial:
      return MundoFicha(persona: mariaDePrueba(telefono: null))
        ..conEdicion = true
        ..conRegistrarVisita = true;
    case EstadoFicha.cargando:
      return MundoFicha(cargando: true);
    case EstadoFicha.error:
      return MundoFicha()..fichas.errorAlObservar = StateError('x');
    case EstadoFicha.deptoDeBaja:
    case EstadoFicha.reactivandoDepto:
      final m = MundoFicha(
        historial: historialDelCanvas(),
        notasIniciales: notasDeLaFicha(),
        contexto: contextoDeptoDeBaja,
        lugarInicial: (
          espacio: espacioDePersonas(numeroDepto: '3B', deletedAt: DateTime.utc(2026, 10, 20)),
          ubicacion: ubicacionDePersonas(),
        ),
      );
      m.cuentas.cuenta = cuentaConSaldo;
      return m;
    case EstadoFicha.personaNoEncontrada:
      final m = MundoFicha();
      m.fichas.poner(null);
      return m;
    case EstadoFicha.sinMovimientos:
      return MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
    case EstadoFicha.conEntregasYCobros:
      final m = mundoCompleto563();
      conEntregasYCobros563(m);
      return m;
    case EstadoFicha.muchosMovimientos:
      final m = mundoCompleto563();
      m.fichas.poner(
        LecturaDeFicha(
          persona: mariaDePrueba(),
          historial: [
            for (var i = 0; i < 130; i++)
              visitaEnFicha(
                'vis-${i.toString().padLeft(3, '0')}',
                DateTime(2026, 6, 1).add(Duration(hours: i * 7)),
              ),
          ],
        ),
      );
      return m;
    case EstadoFicha.textosLargos:
      final m = MundoFicha(
        persona: clienteDePersonas(
          'per-1',
          'María de los Ángeles Candelaria',
          apellido: 'Fernández de la Peña y Rodríguez Altamirano',
          telefono: '+598 99 123 456 789',
        ).persona,
        historial: [
          VentaEnFicha(
            id: 'v',
            fecha: DateTime(2026, 10, 12),
            numeroTalonario: '0042',
            montoCentavos: 123456789,
            lineas: [
              for (var i = 0; i < 6; i++)
                LineaDeFicha(nombre: 'Un libro con un título larguísimo número $i', cantidad: 2),
            ],
          ),
        ],
        notasIniciales: [notaDePrueba('n', 'palabra ' * 80)],
        lugarInicial: (
          espacio: espacioDePersonas(numeroDepto: 'PB-A fondo izquierda'),
          ubicacion: ubicacionDePersonas(calle: 'Avenida General Don José Gervasio Artigas'),
        ),
      );
      m.cuentas.cuenta = const ResumenCuentaPersona(
        compradoCentavos: 123456789,
        pagadoCentavos: 100000000,
        saldoCentavos: 23456789,
        entregasHechas: 12,
        entregasTotales: 30,
      );
      return m;
  }
}

/// Monta la ficha a [tamano] y [escala] y la lleva a [estado].
Future<MundoFicha> llegarAFicha(
  WidgetTester tester,
  EstadoFicha estado, {
  Size tamano = telefonoChico563,
  double escala = 1,
}) async {
  await cargarFuentes563(tester);
  final m = mundoDe563(estado);
  if (estado == EstadoFicha.reactivandoPersona) {
    m.personas.compuertaReactivar = Completer<void>();
  }
  if (estado == EstadoFicha.reactivandoDepto) m.espacios.compuertaRestaurar = Completer<void>();
  await montarFicha(
    tester,
    m,
    tamano: tamano,
    escala: escala,
    lector: estado == EstadoFicha.conLector,
  );
  switch (estado) {
    case EstadoFicha.telefonoVisible:
      await traer563(tester, find.text('Ver'));
      await tester.tap(find.text('Ver'));
      await asentar(tester);
    case EstadoFicha.menuAbierto:
      await tester.tap(find.byKey(ClavesFicha.menu));
      await asentar(tester);
    case EstadoFicha.reactivandoPersona:
      await traer563(tester, find.byKey(ClavesFicha.botonReactivar));
      await tester.tap(find.byKey(ClavesFicha.botonReactivar));
      await tester.pump(const Duration(milliseconds: 60));
    case EstadoFicha.reactivandoDepto:
      await traer563(tester, find.byKey(ClavesFicha.botonReactivarDepto));
      await tester.tap(find.byKey(ClavesFicha.botonReactivarDepto));
      await tester.pump(const Duration(milliseconds: 60));
    case EstadoFicha.errorAlReactivar:
      m.personas.resultadosReactivar.add(const FailureInesperado());
      await traer563(tester, find.byKey(ClavesFicha.botonReactivar));
      await tester.tap(find.byKey(ClavesFicha.botonReactivar));
      await asentar(tester);
    case EstadoFicha.filtroConSaldo:
      await llegarA563(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo)));
      await tester.tap(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo)));
      await asentar(tester);
    case EstadoFicha.filtroSinResultados:
      await llegarA563(tester, find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));
      await tester.tap(find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente)));
      await asentar(tester);
    case EstadoFicha.noPudoLlamar:
      m.marcador.abre = false;
      await traer563(tester, find.byKey(ClavesFicha.botonLlamar));
      await tester.tap(find.byKey(ClavesFicha.botonLlamar));
      await asentar(tester);
    default:
      break;
  }
  return m;
}

/// Lleva [finder] a la vista aunque la lista perezosa todavía no lo haya armado.
Future<void> llegarA563(WidgetTester tester, Finder finder) async {
  final lista = find.byType(Scrollable).first;
  await tester.drag(lista, const Offset(0, 20000));
  await tester.pump();
  await tester.scrollUntilVisible(finder, 300, scrollable: lista);
  await traer563(tester, finder);
}

/// Lleva [finder] a la vista (la ficha es una lista).
Future<void> traer563(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 2; i++) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
}

/// Como [montarFicha] pero con [repo] en lugar del repositorio de fichas del [mundo].
Future<void> montarFichaConRepo563(
  WidgetTester tester,
  MundoFicha mundo,
  FichaPersonaRepository repo,
) async {
  tester.view.physicalSize = telefonoGrande563;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fichaPersonaRepositoryProvider.overrideWithValue(repo),
        notaPersonaRepositoryProvider.overrideWithValue(mundo.notas),
        espacioRepositoryProvider.overrideWithValue(mundo.espacios),
        cuentasDePersonasProvider.overrideWithValue(mundo.cuentas),
        movimientosDeCuentaProvider.overrideWithValue(mundo.movimientos),
        marcadorDeTelefonoProvider.overrideWithValue(mundo.marcador),
        personaRepositoryProvider.overrideWithValue(mundo.personas),
        relojPersonaProvider.overrideWithValue(() => ahoraFicha),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: const FichaPersonaPage(personaId: 'per-1', espacioId: 'esp-1', colportorId: 'col-1'),
      ),
    ),
  );
  await asentar(tester);
}
