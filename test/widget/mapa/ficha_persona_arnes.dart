// Arnés de los tests de la ficha de una persona (HU-UBI-009, vista 32B): monta una pantalla de
// arranque con un botón que abre la ficha, con los dobles de `ficha_persona_falsos.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/restaurar_espacio_use_case.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/ficha_persona_falsos.dart';
import '../../helpers/nota_persona_falsos.dart';
import '../../helpers/persona_falsos.dart';
import 'baja_persona_arnes.dart' show CuentasFalsas;

export 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
export 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
export 'package:colportores_mobile/features/mapa/domain/repositories/ficha_persona_repository.dart';

export '../../helpers/ficha_persona_falsos.dart';
export '../../helpers/nota_persona_falsos.dart';
export '../../helpers/persona_falsos.dart';
export 'baja_persona_arnes.dart' show CuentasFalsas, cuentaConSaldo;

/// «Hoy» de los tests: el 22/10/2026 a las 15:00, hora local.
final ahoraFicha = DateTime(2026, 10, 22, 15);

Future<void> asentar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// [EspacioRepository] de la ficha: `buscar` devuelve [lugar] y `restaurar` toma el siguiente
/// resultado de [resultadosRestaurar] (`null` = éxito).
final class EspacioFichaFalso implements EspacioRepository {
  EspacioFichaFalso(this.lugar);

  EspacioConUbicacion? lugar;
  final resultadosRestaurar = <Failure?>[];
  Completer<void>? compuertaRestaurar;
  final restauraciones = <String>[];

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async => Right(lugar);

  @override
  Future<Either<Failure, Espacio>> restaurar(String id, {required DateTime ahora}) async {
    restauraciones.add(id);
    await compuertaRestaurar?.future;
    final r = resultadosRestaurar.isEmpty ? null : resultadosRestaurar.removeAt(0);
    if (r != null) return Left(r);
    return Right(lugar!.espacio);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Todo lo que la ficha usa, a mano del test.
final class MundoFicha {
  MundoFicha({
    Persona? persona,
    List<MovimientoDeFicha> historial = const [],
    List<NotaPersona> notasIniciales = const [],
    ContextoNotasPersona? contexto,
    EspacioConUbicacion? lugarInicial,
    bool cargando = false,
  }) : fichas = FichaPersonaRepositorioFalso(
         persona: persona ?? mariaDePrueba(),
         historial: historial,
       ),
       notas = NotaPersonaRepositorioFalso(
         notas: notasIniciales,
         contexto: contexto ?? const ContextoNotasPersona(nombre: 'María'),
       ),
       espacios = EspacioFichaFalso(
         lugarInicial ??
             (espacio: espacioDePersonas(numeroDepto: '3B'), ubicacion: ubicacionDePersonas()),
       ) {
    if (cargando) fichas.sinLectura();
  }

  final FichaPersonaRepositorioFalso fichas;
  final NotaPersonaRepositorioFalso notas;
  final EspacioFichaFalso espacios;
  final cuentas = CuentasFalsas();
  final movimientos = MovimientosFalsos();
  final marcador = MarcadorFalso();
  final personas = PersonaRepositorioFalso();

  /// Las veces que se tocó «Editar persona» y con qué persona.
  final ediciones = <String>[];

  /// Los destinos de «Registrar visita».
  final visitas = <ContextoDeVisitaFicha>[];

  /// Lo que devuelve la edición, si queda esperando.
  Completer<void>? compuertaEdicion;

  /// Las ventas que se tocaron para devolverlas (vista 31, HU-VEN-004).
  final devoluciones = <ContextoDeDevolucion>[];

  /// Lo que devuelve el destino de la devolución, si queda esperando.
  Completer<void>? compuertaDevolucion;

  var conEdicion = false;
  var conRegistrarVisita = false;
  var conDevolucion = false;

  /// Con destino para tocar un cobro del historial (vista 30 B): guarda cada `id` que se abrió.
  var conVerCobro = false;
  final cobrosAbiertos = <String>[];
}

typedef ContextoDeVisitaFicha = ({String ubicacionId, String? espacioId, String? agendaId});

/// El contexto de las notas de una persona de baja desde el 22/10.
const contextoPersonaDeBaja = ContextoNotasPersona(
  nombre: 'María',
  causa: CausaSoloLectura.personaDeBaja,
);

ContextoNotasPersona contextoBajaDesde22() => ContextoNotasPersona(
  nombre: 'María',
  causa: CausaSoloLectura.personaDeBaja,
  bajaDesde: DateTime(2026, 10, 22),
);

const contextoDeptoDeBaja = ContextoNotasPersona(
  nombre: 'María',
  causa: CausaSoloLectura.espacioDeBaja,
  numeroDepto: '3B',
  direccion: 'Mataojo 2044',
);

/// Monta el arranque con «abrir ficha» y, si [abrir], lo toca.
Future<void> montarFicha(
  WidgetTester tester,
  MundoFicha mundo, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  bool lector = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var contador = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fichaPersonaRepositoryProvider.overrideWithValue(mundo.fichas),
        notaPersonaRepositoryProvider.overrideWithValue(mundo.notas),
        espacioRepositoryProvider.overrideWithValue(mundo.espacios),
        cuentasDePersonasProvider.overrideWithValue(mundo.cuentas),
        movimientosDeCuentaProvider.overrideWithValue(mundo.movimientos),
        marcadorDeTelefonoProvider.overrideWithValue(mundo.marcador),
        personaRepositoryProvider.overrideWithValue(mundo.personas),
        restaurarEspacioUseCaseProvider.overrideWithValue(RestaurarEspacioUseCase(mundo.espacios)),
        relojPersonaProvider.overrideWithValue(() => ahoraFicha),
        generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++contador}'),
        if (mundo.conEdicion)
          editarPersonaDesdeLaFichaProvider.overrideWithValue((id) async {
            mundo.ediciones.add(id);
            await mundo.compuertaEdicion?.future;
            return null;
          }),
        if (mundo.conVerCobro)
          verCobroDesdeLaFichaProvider.overrideWithValue((id) {
            mundo.cobrosAbiertos.add(id);
            return null;
          }),
        if (mundo.conDevolucion)
          devolverVentaDesdeLaFichaProvider.overrideWithValue((c) async {
            mundo.devoluciones.add(c);
            await mundo.compuertaDevolucion?.future;
            return true;
          }),
        if (mundo.conRegistrarVisita)
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((c) {
            mundo.visitas.add(c);
            return null;
          }),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => FichaPersonaPage.abrir(
                  context,
                  personaId: 'per-1',
                  espacioId: 'esp-1',
                  colportorId: 'col-1',
                ),
                child: const Text('abrir ficha'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir ficha'));
    await asentar(tester);
  }
}

/// Vuelve atrás con el botón de la ficha y deja correr la animación.
Future<void> volverAtras(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Volver'));
  await asentar(tester);
}

/// Las notas del canvas 32B·01: la de hoy a las 14:20 y la del 05/10 (son «1 DE 2»).
List<NotaPersona> notasDeLaFicha() => [
  notaDePrueba(
    'hoy',
    'Pidió volver el sábado con el esposo.',
    creada: DateTime(2026, 10, 22, 14, 20),
  ),
  notaDePrueba('vieja', 'Trabaja en la farmacia.', creada: DateTime(2026, 10, 5, 9)),
];

/// El historial del canvas 32B·01 sin entregas ni cobros: una venta y una visita.
List<MovimientoDeFicha> historialDelCanvas() => [
  VentaEnFicha(
    id: 'ven-1',
    fecha: DateTime(2026, 10, 12, 12),
    numeroTalonario: '0042',
    montoCentavos: 120000,
    lineas: const [
      LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
      LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1),
    ],
  ),
  VisitaEnFicha(
    id: 'vis-1',
    fecha: DateTime(2026, 10, 5, 12),
    resultado: TipoResultadoVisita.entrevista,
  ),
];
