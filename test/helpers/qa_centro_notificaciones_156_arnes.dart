// Arnés de la QA del centro de notificaciones (#156, PR #481): los siete estados del canvas (24C·01
// a 24C·07) llevados a un tamaño y una escala de texto, sobre los falsos de
// `historial_notificaciones_falsos.dart`.
import 'dart:async';

import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'historial_notificaciones_falsos.dart';

/// Un tamaño de pantalla de referencia del proyecto.
typedef Tamano = ({String nombre, double ancho, double alto});

const tamanos = <Tamano>[
  (nombre: '360x640', ancho: 360, alto: 640),
  (nombre: '412x915', ancho: 412, alto: 915),
];

const escalas = <double>[1.0, 2.0];

/// Los estados del centro, uno por artboard (más los que el canvas no dibuja).
enum EstadoCentro {
  lista('24C·01 lista'),
  menu('24C·02 menú'),
  menuSinNuevas('24C·02 menú, nada sin leer'),
  confirmar('24C·03 confirmar'),
  confirmarBorrando('24C·03 borrando'),
  confirmarConError('24C·03 falla al borrar'),
  vacio('24C·04 vacío'),
  cargando('24C·05 cargando'),
  error('24C·06 error al leer'),
  sinDestino('24C·07 el detalle ya no existe'),
  avisosLargos('24C·01 textos largos'),
  muchos('24C·01 300 avisos');

  const EstadoCentro(this.rotulo);
  final String rotulo;
  String get id => name;
}

/// Cinco avisos en cuatro días, tres sin leer (los del canvas 24C·01).
List<Notificacion> cincoDelCanvas() => [
  aviso('a'),
  aviso(
    'b',
    hace: const Duration(hours: 5),
    titulo: 'Entrevista a las 11:30',
    detalle: 'Av. Italia 2810',
    leida: true,
  ),
  aviso(
    'c',
    hace: const Duration(hours: 26),
    titulo: 'Cobranza a las 14:30',
    detalle: 'Grecia 3310',
  ),
  aviso('d', hace: const Duration(days: 3), titulo: 'Entrevista a las 10:00', detalle: null),
  aviso('e', hace: const Duration(days: 10), leida: true),
];

/// Avisos con el texto más largo que puede traer una dirección y palabras sin cortes.
List<Notificacion> avisosLargos() => [
  aviso(
    'l1',
    titulo: 'Cobranza a las 16:00 con la familia Rodríguez-Fernández de la Cuadra Salaverry',
    detalle:
        'Avenida General José Gervasio Artigas esquina Doctor Alejandro Gallinal, apartamento 1204 '
        'torre norte, Montevideo',
  ),
  aviso('l2', hace: const Duration(hours: 2), titulo: 'A' * 80, detalle: 'B' * 120),
  aviso(
    'l3',
    hace: const Duration(hours: 3),
    titulo: 'Visita 🏠 con emoji 👨‍👩‍👧‍👦 y señal <b>&amp;</b> "comillas" \'simples\'',
    detalle: '日本語の住所 · Ñandú 1234 · ½ cuadra',
  ),
  aviso('l4', hace: const Duration(hours: 4), titulo: 'Corto', detalle: ''),
];

List<Notificacion> trescientos() => [
  for (var i = 0; i < 300; i++)
    aviso(
      'm-$i',
      hace: Duration(minutes: 20 + i * 37),
      titulo: 'Cobranza ${i + 1} a las 16:00',
      detalle: 'Calle ${i + 1} esquina ${i + 2}',
      leida: i % 3 == 0,
    ),
];

/// Lleva el centro al [estado] a ese tamaño y escala. Devuelve el arnés con el que quedó montado.
Future<CentroArnes> llevarAlEstado(
  WidgetTester tester,
  EstadoCentro estado, {
  required Tamano tamano,
  required double escala,
}) async {
  final avisos = switch (estado) {
    EstadoCentro.vacio => <Notificacion>[],
    EstadoCentro.menuSinNuevas => [for (final a in cincoDelCanvas()) _leida(a)],
    EstadoCentro.avisosLargos => avisosLargos(),
    EstadoCentro.muchos => trescientos(),
    _ => cincoDelCanvas(),
  };
  final arnes = CentroArnes(avisos: avisos);
  switch (estado) {
    case EstadoCentro.error:
      arnes.historial.errorAlObservar = StateError('no se pudo leer');
    case EstadoCentro.cargando:
      arnes.historial.puertaAlObservar = Completer<void>();
    case EstadoCentro.confirmarConError:
      arnes.historial.fallaAlBorrar = true;
    case EstadoCentro.confirmarBorrando:
      arnes.historial.puertaAlBorrar = Completer<void>();
    case EstadoCentro.sinDestino:
      arnes.destinos.todosExisten = false;
    default:
      break;
  }
  await abrirCentro(
    tester,
    arnes,
    tamano: Size(tamano.ancho, tamano.alto),
    texto: escala,
    esperar: estado != EstadoCentro.cargando,
  );
  switch (estado) {
    case EstadoCentro.menu || EstadoCentro.menuSinNuevas:
      await tester.tap(centroMenu);
      await tester.pumpAndSettle();
    case EstadoCentro.confirmar:
      await _hastaConfirmar(tester);
    case EstadoCentro.confirmarConError:
      await _hastaConfirmar(tester);
      await tester.ensureVisible(borrarConfirmar);
      await tester.tap(borrarConfirmar);
      await tester.pumpAndSettle();
    case EstadoCentro.confirmarBorrando:
      await _hastaConfirmar(tester);
      await tester.ensureVisible(borrarConfirmar);
      await tester.tap(borrarConfirmar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    case EstadoCentro.sinDestino:
      await tester.tap(filaDe('a'));
      await tester.pumpAndSettle();
    default:
      break;
  }
  return arnes;
}

Notificacion _leida(Notificacion a) => Notificacion(
  id: a.id,
  tipo: a.tipo,
  titulo: a.titulo,
  detalle: a.detalle,
  destino: a.destino,
  recibidaEn: a.recibidaEn,
  leidaEn: ahoraDelCentro,
);

Future<void> _hastaConfirmar(WidgetTester tester) async {
  await tester.tap(centroMenu);
  await tester.pumpAndSettle();
  await tester.ensureVisible(menuBorrarTodas);
  await tester.tap(menuBorrarTodas);
  await tester.pumpAndSettle();
}
