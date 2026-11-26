// Arnés de los tests de QA de la nota del depto (vista 11, «Nota del depto», 11N·01 a 11N·07, #290,
// PR #776): lleva la hoja real de la casa (un edificio con deptos), con el enganche de `main.dart`, a cada
// estado que una persona puede ver de la nota del depto (la fila de la hoja C·10, la lista de deptos
// C·09, el formulario y la pestaña Notas del depto) y saca capturas.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/290_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resumen_del_depto.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/deptos_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/fila_nota_del_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestanas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/notas_lugar_arnes.dart' show ahoraDeLugar, asentarLugar;
import 'agenda_items_falsos.dart';
import 'espacios_falsos.dart';
import 'modificar_ubicacion_falsos.dart';
import 'nota_ubicacion_falsos.dart';
import 'persona_falsos.dart';

export '../widget/mapa/notas_lugar_arnes.dart' show asentarLugar, ContadorDeRutas;
export 'qa_baja_205_arnes.dart' show cargarFuentes205;
export 'qa_vista39_445_arnes.dart' show t360x640, t412x915, t320x568;

const conCapturas290 = bool.fromEnvironment('QA_CAPTURAS');

final raizCaptura290 = GlobalKey();

/// El edificio y los deptos de los tests.
const ubicacion290 = 'ubi-1';
const depto3B = 'd-3b';
const depto1A = 'd-1a';

final espacio3B = espacioDe(depto3B, '3B', piso: '3', orden: 3);
final espacio1A = espacioDe(depto1A, '1A', piso: '1', orden: 1);
final espacio2A = espacioDe('d-2a', '2A', piso: '2', orden: 2);

/// El texto del canvas 11N·03.
const textoCanvas290 = 'timbre roto, tocar fuerte';

/// El texto largo del canvas 11N·05.
const textoLargoCanvas290 =
    'Portero de 8 a 12. Después de las 12 tocar el 3B desde la calle; el timbre suena bajo, golpear la '
    'reja.';

NotaUbicacion notaDeDepto(
  String id,
  String texto, {
  String duenio = depto3B,
  DateTime? creada,
  DateTime? borrada,
}) => notaDeLugar(id, texto, ubicacionId: duenio, creada: creada, borrada: borrada);

/// Lo que un test necesita después de montar la hoja.
final class Montaje290 {
  Montaje290(this.notasDeptos, this.notasEdificio);

  final NotaUbicacionRepositorioFalso notasDeptos;
  final NotaUbicacionRepositorioFalso notasEdificio;
  var cierres = 0;
}

Future<Montaje290> montarHoja290(
  WidgetTester tester, {
  NotaUbicacionRepositorioFalso? notasDeptos,
  NotaUbicacionRepositorioFalso? notasEdificio,
  List<NotaUbicacion> notas = const [],
  String? colportorId = 'col-1',
  DateTime? baja,
  bool arriba = false,
  double escala = 1,
  Size tamano = const Size(412, 915),
  Map<String, ResumenDelDepto>? resumen,
  bool elegirDepto = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ubicacion = ubicacionGuardada(
    id: ubicacion290,
    tipo: TipoUbicacion.edificio,
    calle: 'Mataojo',
    numero: '2044',
    deBajaDesde: baja,
  );
  final m = Montaje290(
    notasDeptos ?? NotaUbicacionRepositorioFalso(notas: [...notas]),
    notasEdificio ?? NotaUbicacionRepositorioFalso(),
  );
  var secuencia = 0;
  final item = ItemListaUbicacion(
    ubicacion: ubicacion,
    estado: EstadoCasa.cobranzaPendiente,
    distanciaMetros: 25,
  );
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa()),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        contextoDeLaCasaProvider.overrideWith((ref, clave) {
          final espacioId = clave.espacioId;
          return Stream.value(
            espacioId == null ? const ContextoDeLaCasa() : ContextoDeLaCasa(espacioId: espacioId),
          );
        }),
        registrarVisitaDesdeLaCasaProvider.overrideWithValue((contexto) async => false),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepoFalso(ubicacion, espacios: [espacio3B, espacio1A, espacio2A]),
        ),
        notaDeptoRepositoryProvider.overrideWithValue(m.notasDeptos),
        notaUbicacionRepositoryProvider.overrideWithValue(m.notasEdificio),
        relojPersonaProvider.overrideWithValue(() => ahoraDeLugar),
        generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++secuencia}'),
        pestanaNotasDeLaCasaProvider.overrideWithValue(PestanaNotasDeLaCasa.enganche),
        ubicacionRepositoryProvider.overrideWithValue(RepoEdicionFalso(ubicacion)),
        contadorPersonasEspacioProvider.overrideWithValue(ContadorPersonasFalso()),
        generadorIdEspacioProvider.overrideWithValue(() => 'nuevo-${++secuencia}'),
        relojEspaciosProvider.overrideWithValue(() => ahoraDeLugar),
        resumenDeLosDeptosProvider.overrideWith(
          (ref, clave) => Stream.value(
            resumen ??
                {
                  depto1A: ResumenDelDepto(),
                  'd-2a': ResumenDelDepto(),
                  depto3B: ResumenDelDepto(estado: EstadoCasa.cobranzaPendiente),
                },
          ),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: raizCaptura290, child: child!),
        ),
        home: Scaffold(
          body: HojaCasa(
            item: item,
            ahora: ahoraDeLugar,
            alCerrar: () => m.cierres++,
            colportorId: colportorId,
            arriba: arriba,
          ),
        ),
      ),
    ),
  );
  await asentarLugar(tester);
  if (elegirDepto) {
    await tocar290(tester, find.byKey(ClavesDeptosDeLaCasa.fila(depto3B)));
  }
  return m;
}

/// Toca [que] después de traerlo a la vista (a 360×640 con texto 2× la hoja es más alta que la pantalla).
Future<void> tocar290(WidgetTester tester, Finder que) async {
  await tester.ensureVisible(que);
  await tester.pump();
  await tester.tap(que);
  await asentarLugar(tester);
}

/// Va a la pestaña Notas de la hoja del depto (la hoja arriba).
Future<void> irALaPestanaNotas(WidgetTester tester) async {
  final pestana = find.byKey(ClavesHojaCasa.pestana(PestanaHojaCasa.notas.id));
  await tester.ensureVisible(pestana);
  await tester.pump();
  await tester.tap(pestana);
  await asentarLugar(tester);
}

/// Una captura PNG de lo que se ve en `.dart_tool/qa_capturas/290_<nombre>.png`, solo con `QA_CAPTURAS`.
Future<void> capturar290(WidgetTester tester, String nombre) async {
  if (!conCapturas290) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/290_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo290(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Los estados de la nota del depto que una persona puede alcanzar.
enum Estado290 {
  /// 11N·01
  sinNota,

  /// 11N·03
  conNota,

  /// 11N·05
  notaLarga,

  /// 5000 caracteres seguidos, emoji y palabras largas.
  notaExtrema,

  /// Varias notas (la fila muestra la más nueva).
  variasNotas,

  /// Cargando: la fila no dibuja nada.
  cargando,

  /// Error al leer.
  errorAlLeer,

  /// Edificio dado de baja, con nota.
  deBajaConNota,

  /// Edificio dado de baja, sin nota.
  deBajaSinNota,

  /// Sin sesión.
  sinSesion,

  /// 11N·02
  formularioNuevo,

  /// 11N·04
  formularioEditar,

  /// 11N·07
  formularioError,

  /// Pasa de 5000 caracteres.
  formularioNotaLarga,

  /// C·09 / 11N·06
  listaConNota,

  /// La lista con una nota larga y 2x.
  listaConNotaLarga,

  /// Pestaña Notas del depto, sin notas.
  pestanaVacia,

  /// Pestaña Notas del depto, con notas.
  pestanaConNotas,

  /// La pestaña, con el aviso de «Deshacer» después de borrar.
  pestanaAvisoBorrada,

  /// La pestaña, con el aviso de que no se pudo borrar.
  pestanaAvisoFalla,

  /// «Ver borradas» del depto.
  borradasDelDepto,
}

Future<Montaje290> llegarA290(
  WidgetTester tester,
  Estado290 estado, {
  Size tamano = const Size(412, 915),
  double escala = 1,
}) async {
  Future<Montaje290> m({
    NotaUbicacionRepositorioFalso? repo,
    List<NotaUbicacion> notas = const [],
    String? colportorId = 'col-1',
    DateTime? baja,
    bool arriba = false,
    bool elegirDepto = true,
    Map<String, ResumenDelDepto>? resumen,
  }) => montarHoja290(
    tester,
    notasDeptos: repo,
    notas: notas,
    colportorId: colportorId,
    baja: baja,
    arriba: arriba,
    escala: escala,
    tamano: tamano,
    elegirDepto: elegirDepto,
    resumen: resumen,
  );

  final canvas = notaDeDepto('c1', textoCanvas290, creada: DateTime(2026, 10, 22, 14, 20));
  switch (estado) {
    case Estado290.sinNota:
      return m();
    case Estado290.conNota:
      return m(notas: [canvas]);
    case Estado290.notaLarga:
      return m(notas: [notaDeDepto('l', textoLargoCanvas290)]);
    case Estado290.notaExtrema:
      return m(
        notas: [
          notaDeDepto(
            'x',
            '${'Clave: ${'A1B2C3D4' * 20} 😀👍🏽 ${'ñandú ' * 40}' * 2}${'Portón verde. ' * 300}FIN',
          ),
        ],
      );
    case Estado290.variasNotas:
      return m(
        notas: [
          canvas,
          for (var i = 0; i < 6; i++)
            notaDeDepto(
              'v$i',
              'Nota vieja número $i',
              creada: DateTime(2026, 9, 1).add(Duration(days: i)),
            ),
        ],
      );
    case Estado290.cargando:
      return m(repo: NotaUbicacionRepositorioCargando());
    case Estado290.errorAlLeer:
      return m(repo: NotaUbicacionRepositorioQueFallaUnaVez(notas: [canvas]));
    case Estado290.deBajaConNota:
      return m(notas: [canvas], baja: DateTime.utc(2026, 10, 18, 12));
    case Estado290.deBajaSinNota:
      return m(baja: DateTime.utc(2026, 10, 18, 12));
    case Estado290.sinSesion:
      return m(notas: [canvas], colportorId: null);
    case Estado290.formularioNuevo:
      final r = await m();
      await tocar290(tester, find.byKey(ClavesNotaDelDepto.agregar));
      return r;
    case Estado290.formularioEditar:
      final r = await m(notas: [canvas]);
      await tocar290(tester, find.byKey(ClavesNotaDelDepto.editar));
      return r;
    case Estado290.formularioError:
      final repo = NotaUbicacionRepositorioFalso()
        ..resultados['agregar'] = [const FailureInesperado(causa: 'x')];
      final r = await m(repo: repo);
      await tocar290(tester, find.byKey(ClavesNotaDelDepto.agregar));
      await tester.enterText(find.byKey(ClavesNotas.campo), textoCanvas290);
      await tester.pump();
      await tocar290(tester, find.text('Guardar nota'));
      return r;
    case Estado290.formularioNotaLarga:
      final r = await m();
      await tocar290(tester, find.byKey(ClavesNotaDelDepto.agregar));
      await tester.enterText(find.byKey(ClavesNotas.campo), 'x' * 6000);
      await asentarLugar(tester);
      return r;
    case Estado290.listaConNota:
      return m(
        notas: [canvas],
        elegirDepto: false,
        resumen: {
          depto1A: ResumenDelDepto(),
          'd-2a': ResumenDelDepto(),
          depto3B: ResumenDelDepto(notaMasNueva: textoCanvas290),
        },
      );
    case Estado290.listaConNotaLarga:
      return m(
        elegirDepto: false,
        resumen: {
          depto1A: ResumenDelDepto(notaMasNueva: 'Ñ' * 5000),
          'd-2a': ResumenDelDepto(notaMasNueva: textoLargoCanvas290),
          depto3B: ResumenDelDepto(notaMasNueva: '😀' * 300),
        },
      );
    case Estado290.pestanaVacia:
      final r = await m(arriba: true);
      await irALaPestanaNotas(tester);
      return r;
    case Estado290.pestanaConNotas:
      final r = await m(
        arriba: true,
        notas: [
          canvas,
          notaDeDepto('c2', textoLargoCanvas290, creada: DateTime(2026, 10, 5, 9)),
          notaDeDepto('c3', 'Mejor después de las 18.', creada: DateTime(2026, 10, 3, 18)),
        ],
      );
      await irALaPestanaNotas(tester);
      return r;
    case Estado290.pestanaAvisoBorrada:
      final r = await m(
        arriba: true,
        notas: [
          canvas,
          notaDeDepto('c2', textoLargoCanvas290, creada: DateTime(2026, 10, 5, 9)),
        ],
      );
      await irALaPestanaNotas(tester);
      await borrarPorMenu290(tester, 'c1');
      return r;
    case Estado290.pestanaAvisoFalla:
      final repo = NotaUbicacionRepositorioFalso(notas: [canvas])
        ..resultados['borrar'] = [const FailureInesperado(causa: 'x')];
      final r = await m(arriba: true, repo: repo);
      await irALaPestanaNotas(tester);
      await borrarPorMenu290(tester, 'c1');
      return r;
    case Estado290.borradasDelDepto:
      final r = await m(
        arriba: true,
        notas: [
          canvas,
          notaDeDepto(
            'b1',
            'Una que borré',
            creada: DateTime(2026, 9, 30, 10),
            borrada: DateTime(2026, 10, 1),
          ),
        ],
      );
      await irALaPestanaNotas(tester);
      await tester.ensureVisible(find.byKey(ClavesNotasDelLugar.verBorradas));
      await tester.tap(find.byKey(ClavesNotasDelLugar.verBorradas));
      await asentarLugar(tester);
      return r;
  }
}

/// Borra la nota [id] por la hoja de opciones de la pestaña, como lo hace la persona.
Future<void> borrarPorMenu290(WidgetTester tester, String id) async {
  final tarjeta = find.byKey(ClavesNotasDelLugar.nota(id));
  await tester.ensureVisible(tarjeta);
  await tester.tap(tarjeta);
  await asentarLugar(tester);
  await tester.tap(find.byKey(ClavesNotas.botonBorrar));
  await asentarLugar(tester);
}
