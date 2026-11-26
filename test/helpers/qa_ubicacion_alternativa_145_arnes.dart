// Arnés de QA de #145 (HU-UBI-013, vista 22 grupo A): arma cada estado de la sección «COBRANZA» de la
// ficha, del selector «¿Dónde le cobrás?» y de la hoja «¿Quitar …?» sobre el arnés de la ficha, en el
// tamaño y con el texto que se pida. Lo usan las guías, el contraste y las capturas.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/ficha_persona_arnes.dart';

export '../widget/mapa/ficha_persona_arnes.dart' show MundoFicha, asentar, montarFicha;

const tamanos145 = [Size(360, 640), Size(412, 915)];
const escalas145 = [1.0, 2.0];

final italia145 = ubicacionParaAlternativa('ub-2');
final italiaDeBaja145 = ubicacionParaAlternativa('ub-2', deletedAt: DateTime(2026, 10, 20));
final casa145 = ubicacionParaAlternativa(
  'ub-3',
  calle: 'Mataojo',
  numero: '2051',
  tipo: TipoUbicacion.casa,
);

MundoFicha mundo145({
  EstadoUbicacionAlternativa estado = const SinUbicacionAlternativa(),
  List<Ubicacion>? candidatas,
  bool personaDeBaja = false,
}) {
  final m = personaDeBaja
      ? MundoFicha(
          persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
          historial: historialDelCanvas(),
          contexto: contextoBajaDesde22(),
        )
      : MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha());
  m.alternativas
    ..ponerEstado(estado)
    ..ponerCandidatas(candidatas ?? [italia145, casa145]);
  return m;
}

/// Baja la ficha hasta [objetivo] (la lista es perezosa: hay que desplazarse hasta que exista).
Future<void> bajarHasta145(WidgetTester tester, Finder objetivo) async {
  await tester.scrollUntilVisible(objetivo, 300, scrollable: find.byType(Scrollable).first);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Baja la ficha hasta la sección «COBRANZA»; si no llega, el test falla (no pasa en vacío).
Future<void> irALaSeccion145(WidgetTester tester) async {
  final seccion = find.byKey(ClavesAlternativa.seccion);
  await bajarHasta145(tester, seccion);
  expect(seccion, findsOneWidget);
}

Future<void> tocarEnLaFicha145(WidgetTester tester, Finder f) async {
  await bajarHasta145(tester, f);
  await tester.tap(f);
  await asentar(tester);
}

typedef Preparar145 = Future<void> Function(WidgetTester tester, Size tamano, double escala);

Future<void> enLaFicha145(WidgetTester tester, MundoFicha m, Size tamano, double escala) async {
  await montarFicha(tester, m, tamano: tamano, escala: escala);
  await irALaSeccion145(tester);
}

/// Los estados de la vista 22A, cada uno con cómo se llega a él.
final estados145 = <String, Preparar145>{
  '22A·01 sin alternativa': (t, tam, esc) => enLaFicha145(t, mundo145(), tam, esc),
  'cargando dónde se le cobra': (t, tam, esc) =>
      enLaFicha145(t, mundo145()..alternativas.sinLectura(), tam, esc),
  'error al leer dónde se le cobra': (t, tam, esc) =>
      enLaFicha145(t, mundo145()..alternativas.errorAlObservar = StateError('sin db'), tam, esc),
  '22A·06 vigente': (t, tam, esc) =>
      enLaFicha145(t, mundo145(estado: UbicacionAlternativaVigente(italia145)), tam, esc),
  '22A·08 dada de baja': (t, tam, esc) => enLaFicha145(
    t,
    mundo145(estado: UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja145)),
    tam,
    esc,
  ),
  'no está en el teléfono': (t, tam, esc) =>
      enLaFicha145(t, mundo145(estado: const UbicacionAlternativaFaltante('ub-9')), tam, esc),
  'persona de baja con alternativa (solo lectura)': (t, tam, esc) => enLaFicha145(
    t,
    mundo145(estado: UbicacionAlternativaVigente(italia145), personaDeBaja: true),
    tam,
    esc,
  ),
  'guardando…': (t, tam, esc) async {
    final m = mundo145()..alternativas.compuertaEstablecer = Completer<void>();
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.fila('ub-2')));
    await irALaSeccion145(t);
  },
  '22A·09 error al guardar': (t, tam, esc) async {
    final m = mundo145()..alternativas.resultadosEstablecer.add(const FailureInesperado());
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.fila('ub-2')));
    await irALaSeccion145(t);
  },
  '22A·02 selector con ubicaciones': (t, tam, esc) async {
    await enLaFicha145(t, mundo145(), tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
  },
  'selector desde la vigente (Actual)': (t, tam, esc) async {
    await enLaFicha145(t, mundo145(estado: UbicacionAlternativaVigente(italia145)), tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.vigente));
    // La lista es perezosa: con texto grande la fila vigente puede quedar bajo el pliegue.
    await t.scrollUntilVisible(
      find.byKey(ClavesAlternativa.fila('ub-2')),
      200,
      scrollable: find
          .descendant(of: find.byKey(ClavesAlternativa.selector), matching: find.byType(Scrollable))
          .first,
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Actual'), findsOneWidget);
  },
  '22A·03 selector cargando': (t, tam, esc) async {
    final m = mundo145()..alternativas.sinLecturaDeCandidatas();
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
  },
  '22A·04 selector vacío': (t, tam, esc) async {
    await enLaFicha145(t, mundo145(candidatas: const []), tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
  },
  '22A·05 selector sin resultados': (t, tam, esc) async {
    await enLaFicha145(t, mundo145(), tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
    final campo = find.byKey(ClavesAlternativa.selectorBuscar);
    await bajarHasta145(t, campo);
    await t.enterText(campo, 'Bulevar Artigas');
    await asentar(t);
  },
  'selector con error al leer': (t, tam, esc) async {
    final m = mundo145()..alternativas.errorAlObservarCandidatas = StateError('sin db');
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.sinAlternativa));
  },
  '22A·07 hoja de quitar': (t, tam, esc) async {
    await enLaFicha145(t, mundo145(estado: UbicacionAlternativaVigente(italia145)), tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.quitar));
  },
  'hoja de quitar con la falla': (t, tam, esc) async {
    final m = mundo145(estado: UbicacionAlternativaVigente(italia145))
      ..alternativas.resultadosQuitar.add(const FailureInesperado());
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.quitar));
    await t.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
    await asentar(t);
  },
  'hoja de quitar quitando…': (t, tam, esc) async {
    final m = mundo145(estado: UbicacionAlternativaVigente(italia145))
      ..alternativas.compuertaQuitar = Completer<void>();
    await enLaFicha145(t, m, tam, esc);
    await tocarEnLaFicha145(t, find.byKey(ClavesAlternativa.quitar));
    await t.tap(find.byKey(ClavesAlternativa.hojaQuitarConfirmar));
    await t.pump(const Duration(milliseconds: 100));
  },
};
