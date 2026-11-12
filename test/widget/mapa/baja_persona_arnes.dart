// Arnés de los tests de la baja de una persona (HU-UBI-011, vista 32D): monta una pantalla con un botón
// que abre la hoja «¿Dar de baja a …?» y recuerda cómo se cerró.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

/// El instante «ahora» de los tests de la baja.
final ahoraBaja = DateTime.utc(2026, 10, 25, 9, 30);

/// La cuenta del canvas 32D·02: comprado $ 4.500, 1 de 2 entregas, pagado $ 3.300, saldo $ 1.200.
const cuentaConSaldo = ResumenCuentaPersona(
  compradoCentavos: 450000,
  pagadoCentavos: 330000,
  saldoCentavos: 120000,
  entregasHechas: 1,
  entregasTotales: 2,
);

/// [CuentasDePersonas] con lo que se le pida. [secuencia] se consume una por consulta (después queda
/// [cuenta]); [lanza] hace fallar la consulta; [compuerta] la deja esperando.
final class CuentasFalsas implements CuentasDePersonas {
  CuentasFalsas({this.cuenta, this.lanza, this.compuerta, List<Object?>? secuencia})
    : secuencia = secuencia ?? [];

  ResumenCuentaPersona? cuenta;
  Object? lanza;
  Completer<void>? compuerta;
  final List<Object?> secuencia;
  var consultas = 0;

  @override
  Future<ResumenCuentaPersona?> resumenDe(String personaId) async {
    consultas++;
    await compuerta?.future;
    final error = lanza;
    if (error != null) throw error;
    if (secuencia.isNotEmpty) return secuencia.removeAt(0) as ResumenCuentaPersona?;
    return cuenta;
  }
}

/// Lo que la pantalla de arranque recibió al cerrarse la hoja.
final class ResultadoBaja {
  SalidaHojaBajaPersona? salida;
  var cierres = 0;
}

/// La persona de la baja: «Jorge Fernández», o la que se pida.
Persona personaParaBaja({String nombre = 'Jorge', String apellido = 'Fernández'}) =>
    clienteDePersonas('p1', nombre, apellido: apellido).persona;

/// Monta una pantalla con un botón «abrir baja» y, si [abrir], lo toca y deja correr los fotogramas.
Future<ResultadoBaja> montarHojaBaja(
  WidgetTester tester, {
  PersonaRepositorioFalso? repo,
  CuentasDePersonas? cuentas,
  Persona? persona,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final resultado = ResultadoBaja();
  final laPersona = persona ?? personaParaBaja();
  final elRepo = repo ?? (PersonaRepositorioFalso()..sembrar([clienteDePersonas('p1', 'Jorge')]));
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personaRepositoryProvider.overrideWithValue(elRepo),
        cuentasDePersonasProvider.overrideWithValue(cuentas ?? CuentasFalsas()),
        relojPersonaProvider.overrideWithValue(() => ahoraBaja),
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
                onPressed: () async {
                  final s = await mostrarHojaBajaPersona(context, persona: laPersona);
                  resultado
                    ..salida = s
                    ..cierres += 1;
                },
                child: const Text('abrir baja'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir baja'));
    await asentar(tester);
  }
  return resultado;
}
