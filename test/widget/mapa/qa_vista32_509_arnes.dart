// Arnés de la QA de #509 (vista 32: «Ver borradas» con «Se borra el …» en 32E·04/05 y la baja con
// entrega pendiente en 32D·02/03, PR #604): los estados de cada artboard y los que el canvas no dibuja,
// con las fuentes reales del proyecto y la matriz de tamaños y escalas de texto de la QA.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart';
import 'notas_persona_arnes.dart';
import 'qa_vista32d_baja_143_arnes.dart' as base;

export 'qa_vista32d_baja_143_arnes.dart'
    show
        cargarFuentes,
        dentroDeLaPantalla,
        escalas,
        sinTextoCortado,
        tamanos,
        usarFuentesReales,
        verEnPantalla;

/// La pantalla completa (con la hoja modal) como PNG, solo con `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!base.conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tam = tester.view.physicalSize;
    final img = await capa.toImage(Offset.zero & tam);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa509_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

// ---------------------------------------------------------------------------------------------------
// 32E · «Ver borradas»
// ---------------------------------------------------------------------------------------------------

/// Borrada hoy (22/10/2026 a las 14:30): se va el 20/01.
final borradaHoy = DateTime(2026, 10, 22, 14, 30);

/// Borrada el 05/10: se va el 03/01.
final borradaEl0510 = DateTime(2026, 10, 5, 9);

/// Borrada el 24/07 a las 16:00: se va hoy a las 16:00 (a las 15:00 todavía está).
final borradaSeVaHoy = DateTime(2026, 7, 24, 16);

enum EstadoBorradas {
  e04('E04 lista con «Ver borradas (2)»'),
  e05Una('E05 una borrada'),
  e05Tres('E05 tres borradas, una se va hoy'),
  e05TextoLargo('E05 nota larguísima'),
  e05SoloLectura('E05 persona de baja: sin Restaurar'),
  e05Vacia('E05 sin borradas (se restauró la única)'),
  e05Muchas('E05 40 borradas'),
  e05FallaRestaurar('E05 falla al restaurar'),
  e05Restaurando('E05 restaurando');

  const EstadoBorradas(this.rotulo);

  final String rotulo;
}

/// Lo que cada estado de «Ver borradas» necesita para armarse.
final class EscenarioBorradas {
  EscenarioBorradas(this.repo);

  final NotaPersonaRepositorioFalso repo;
}

/// Monta la lista de notas de María en el [estado] y, salvo en E·04, abre «Ver borradas».
Future<EscenarioBorradas> borradasEn(
  WidgetTester tester,
  EstadoBorradas estado, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  bool lector = false,
}) async {
  await base.cargarFuentes(tester);
  final notas = switch (estado) {
    EstadoBorradas.e05Una || EstadoBorradas.e05Vacia => [
      notaDePrueba('b1', 'Pidió volver el sábado con el esposo.', borrada: borradaHoy),
    ],
    EstadoBorradas.e05FallaRestaurar || EstadoBorradas.e05Restaurando => [
      notaDePrueba('b1', 'Pidió volver el sábado con el esposo.', borrada: borradaHoy),
      notaDePrueba('b2', 'Trabaja en la farmacia de Av. Italia.', borrada: borradaEl0510),
    ],
    EstadoBorradas.e05Tres => [
      notaDePrueba('b1', 'Pidió volver el sábado con el esposo.', borrada: borradaHoy),
      notaDePrueba('b2', 'Trabaja en la farmacia de Av. Italia.', borrada: borradaEl0510),
      notaDePrueba('b3', 'Se va hoy a las 16:00.', borrada: borradaSeVaHoy),
      notaDePrueba('activa', 'Sigue activa.', creada: DateTime(2026, 10, 20, 9)),
    ],
    EstadoBorradas.e05TextoLargo => [
      notaDePrueba(
        'b1',
        'Pidió volver el sábado con el esposo y los dos hijos. ' * 8,
        borrada: borradaHoy,
      ),
      notaDePrueba('b2', 'Anotación_sin_espacios_' * 12, borrada: borradaEl0510),
    ],
    EstadoBorradas.e05Muchas => [
      for (var i = 0; i < 40; i++)
        notaDePrueba(
          'm$i',
          'Nota borrada número $i.',
          creada: DateTime(2026, 9, 1, 8, i),
          borrada: DateTime(2026, 9, 1, 9, i),
        ),
    ],
    _ => [
      notaDePrueba('b1', 'Pidió volver el sábado con el esposo.', borrada: borradaHoy),
      notaDePrueba('b2', 'Trabaja en la farmacia de Av. Italia.', borrada: borradaEl0510),
      notaDePrueba('activa', 'Sigue activa.', creada: DateTime(2026, 10, 20, 9)),
    ],
  };
  final repo = NotaPersonaRepositorioFalso(
    contexto: ContextoNotasPersona(
      nombre: 'María',
      causa: estado == EstadoBorradas.e05SoloLectura ? CausaSoloLectura.personaDeBaja : null,
    ),
    notas: notas,
  );
  if (estado == EstadoBorradas.e05FallaRestaurar) {
    repo.resultados['restaurar'] = [const FailureInesperado()];
  }
  await montarNotas(repo: repo, tester, tamano: tamano, escala: escala, lector: lector);
  if (estado == EstadoBorradas.e04) return EscenarioBorradas(repo);

  final cuantas = notas.where((n) => n.estaBorrada).length;
  final enlace = find.text('Ver borradas ($cuantas)');
  await base.verEnPantalla(tester, enlace);
  await tester.tap(enlace);
  await asentar(tester);

  switch (estado) {
    case EstadoBorradas.e05Vacia:
      final boton = find.text('Restaurar').first;
      await base.verEnPantalla(tester, boton);
      await tester.tap(boton);
      await asentar(tester);
    case EstadoBorradas.e05FallaRestaurar:
      final boton = find.text('Restaurar').first;
      await base.verEnPantalla(tester, boton);
      await tester.tap(boton);
      await asentar(tester);
    case EstadoBorradas.e05Restaurando:
      repo.compuertas['restaurar'] = Completer<void>();
      final boton = find.text('Restaurar').first;
      await base.verEnPantalla(tester, boton);
      await tester.tap(boton);
      await asentar(tester);
    default:
  }
  return EscenarioBorradas(repo);
}

// ---------------------------------------------------------------------------------------------------
// 32D · la hoja de baja con entrega pendiente
// ---------------------------------------------------------------------------------------------------

/// Debe $ 0, 1 de 2 entregas: «Jorge tiene 1 entrega pendiente.»
const cuentaSoloUnaEntrega = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 450000,
  saldoCentavos: 0,
  entregasHechas: 1,
  entregasTotales: 2,
);

/// Debe $ 0, 0 de 3 entregas: «Jorge tiene 3 entregas pendientes.»
const cuentaSoloTresEntregas = ResumenCuentaPersona(
  compradoCentavos: 900000,
  pagadoCentavos: 900000,
  saldoCentavos: 0,
  entregasHechas: 0,
  entregasTotales: 3,
);

/// Debe $ 1.200 y 1 entrega pendiente (la del canvas 32D·02).
const cuentaDeudaYEntrega = cuentaConSaldo;

/// Debe $ 1.200 y todo entregado (la deuda sola).
const cuentaSoloDeuda = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 330000,
  saldoCentavos: 120000,
  entregasHechas: 2,
  entregasTotales: 2,
);

/// Todo pagado y todo entregado: se da de baja con una sola confirmación (32D·01).
const cuentaAlDia = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 450000,
  saldoCentavos: 0,
  entregasHechas: 2,
  entregasTotales: 2,
);

/// Más entregas hechas que vendidas (dato raro): no hay pendientes y no pide confirmar.
const cuentaConEntregaDeMas = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 450000,
  saldoCentavos: 0,
  entregasHechas: 3,
  entregasTotales: 2,
);

enum EstadoBaja509 {
  soloUnaEntrega('D02 solo 1 entrega', cuentaSoloUnaEntrega, false),
  soloTresEntregas('D02 solo 3 entregas', cuentaSoloTresEntregas, false),
  deudaYEntrega('D02 deuda y 1 entrega', cuentaDeudaYEntrega, false),
  soloUnaEntregaConfirmar('D03 solo 1 entrega', cuentaSoloUnaEntrega, true),
  soloTresEntregasConfirmar('D03 solo 3 entregas', cuentaSoloTresEntregas, true),
  deudaYEntregaConfirmar('D03 deuda y 1 entrega', cuentaDeudaYEntrega, true);

  const EstadoBaja509(this.rotulo, this.cuenta, this.segunda);

  final String rotulo;
  final ResumenCuentaPersona cuenta;
  final bool segunda;
}

/// Escenario de la hoja ya montado.
final class EscenarioBaja {
  EscenarioBaja({required this.repo, required this.cuentas, required this.resultado});

  final PersonaRepositorioFalso repo;
  final CuentasFalsas cuentas;
  final ResultadoBaja resultado;
}

/// Monta la hoja de baja de [nombre] con la [cuenta] y, con [segunda], la lleva a «¿Seguro?».
Future<EscenarioBaja> hojaConCuenta(
  WidgetTester tester,
  ResumenCuentaPersona cuenta, {
  bool segunda = false,
  Size tamano = const Size(360, 640),
  double escala = 1,
  String nombre = 'Jorge',
  String apellido = 'Fernández',
  CuentasFalsas? cuentas,
}) async {
  await base.cargarFuentes(tester);
  final laCuenta = cuentas ?? CuentasFalsas(cuenta: cuenta);
  final repo = PersonaRepositorioFalso()
    ..sembrar([clienteDePersonas('p1', nombre, apellido: apellido)]);
  final resultado = await montarHojaBaja(
    tester,
    repo: repo,
    cuentas: laCuenta,
    persona: personaParaBaja(nombre: nombre, apellido: apellido),
    tamano: tamano,
    escala: escala,
  );
  if (segunda) {
    await tester.tap(find.text('Dar de baja igual'));
    await asentar(tester);
  }
  return EscenarioBaja(repo: repo, cuentas: laCuenta, resultado: resultado);
}

Future<EscenarioBaja> hojaEn(
  WidgetTester tester,
  EstadoBaja509 estado, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  String nombre = 'Jorge',
  String apellido = 'Fernández',
}) => hojaConCuenta(
  tester,
  estado.cuenta,
  segunda: estado.segunda,
  tamano: tamano,
  escala: escala,
  nombre: nombre,
  apellido: apellido,
);
