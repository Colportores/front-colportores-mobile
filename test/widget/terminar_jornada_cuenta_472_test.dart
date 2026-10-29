// «Terminar jornada» en la pantalla de la cuenta restringida (HU-AUTH-008 + HU-JOR-002, #472,
// seguimiento de #383; decisión de Cristian, 25/10, «Jornada susp.»): si la cuenta quedó pendiente
// o suspendida con la jornada abierta, la persona la termina desde ahí, con la hora de fin que ella
// elige y los mismos textos y validaciones que «Hoy». Nada nuevo se puede empezar.
//
// La vista 18 no dibuja esta sección: el lugar y los textos que no vienen de la decisión están
// marcados en el pendiente de la entrega.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/entrevista_falsos.dart';
import '../helpers/terminar_jornada_cuenta_arnes.dart';

final _seccion = find.byKey(const Key('cuenta_terminar_jornada'));
final _boton = find.byKey(const Key('cuenta_terminar_jornada_boton'));
final _filaFin = find.byKey(const Key('jornada_ajustar_hora_fin'));
final _errorFin = find.byKey(const Key('jornada_error_fin'));
final _resumen = find.byKey(const Key('jornada_resumen'));
const _textoErrorGuardar =
    'No pudimos guardar el fin de tu jornada, que sigue abierta. Probá de nuevo; si sigue '
    'pasando, avisale a tu coordinador.';

void main() {
  late LocalDeJornada local;
  late MontajeEntrevista montaje;

  setUp(() {
    montaje = MontajeEntrevista();
    local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 23, 13, 15))]);
  });

  Future<void> montar(WidgetTester tester, {EstadoCuenta? estado = EstadoCuenta.suspendida}) =>
      montarCuentaConJornada(tester, local: local, montaje: montaje, estado: estado);

  Future<void> tocarTerminar(WidgetTester tester) async {
    await tester.ensureVisible(_boton);
    await tester.tap(_boton);
    await tester.pumpAndSettle();
  }

  Future<void> elegirUnaHoraAntes(WidgetTester tester) async {
    await tester.ensureVisible(_filaFin);
    await tester.tap(_filaFin);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hoja_hora_menos')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('hoja_hora_usar')));
    await tester.pumpAndSettle();
  }

  VoidCallback? alTocar(WidgetTester tester) => tester.widget<FilledButton>(_boton).onPressed;

  group('con la jornada abierta, en cada cuenta que no trabaja', () {
    for (final (nombre, estado) in [
      ('suspendida', EstadoCuenta.suspendida),
      ('pendiente de asignación', EstadoCuenta.pendienteAsignacion),
    ]) {
      testWidgets('cuenta $nombre: aparece «Terminar jornada» con la hora de fin en «Ahora»', (
        tester,
      ) async {
        await montar(tester, estado: estado);

        expect(_seccion, findsOneWidget);
        expect(find.text('Terminar jornada'), findsOneWidget);
        expect(find.byKey(const Key('cuenta_jornada_abierta')), findsOneWidget);
        expect(find.textContaining('desde las 13:15'), findsOneWidget);
        expect(find.byKey(const Key('jornada_hora_fin')), findsOneWidget);
        expect(find.textContaining('Ahora'), findsWidgets);
        expect(alTocar(tester), isNotNull);
      });
    }

    testWidgets('sin estado conocido (sin conexión) también aparece', (tester) async {
      await montar(tester, estado: null);

      expect(_boton, findsOneWidget);
    });

    testWidgets('no ofrece empezar nada nuevo: ni «Iniciar jornada» ni «Abrir el mapa»', (
      tester,
    ) async {
      await montar(tester);

      expect(find.byKey(const Key('jornada_iniciar')), findsNothing);
      expect(find.byKey(const Key('jornada_abrir_mapa')), findsNothing);
      expect(find.text('Iniciar jornada'), findsNothing);
    });
  });

  group('sin jornada abierta no hay nada que terminar', () {
    for (final estado in [EstadoCuenta.suspendida, EstadoCuenta.pendienteAsignacion]) {
      testWidgets('cuenta ${estado.name}: no hay botón ni hora de fin', (tester) async {
        local = LocalDeJornada(const []);
        await montar(tester, estado: estado);

        expect(_seccion, findsNothing);
        expect(find.text('Terminar jornada'), findsNothing);
        expect(_filaFin, findsNothing);
      });
    }

    testWidgets('con la jornada ya cerrada tampoco', (tester) async {
      final cerrada = jornadaAbiertaDesde(
        DateTime(2026, 10, 23, 13, 15),
      ).finalizada(fin: DateTime(2026, 10, 23, 14), actualizadaEn: DateTime(2026, 10, 23, 14));
      local = LocalDeJornada([JornadaModel.fromEntity(cerrada)]);
      await montar(tester);

      expect(_seccion, findsNothing);
    });

    testWidgets('si no se puede leer la jornada, la pantalla de la cuenta sigue entera', (
      tester,
    ) async {
      local.errorAlLeer = StateError('disco');
      await montar(tester);

      expect(_seccion, findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.byKey(const Key('espera_ir_a_configuracion')), findsOneWidget);
    });

    testWidgets('mientras se lee, la sección no ocupa lugar y aparece al llegar la lectura', (
      tester,
    ) async {
      final lectura = local.demoraLectura = Completer<void>();
      await montar(tester);
      await tester.pump();

      expect(_seccion, findsNothing);

      lectura.complete();
      await tester.pumpAndSettle();

      expect(_seccion, findsOneWidget);
    });
  });

  group('terminar la jornada', () {
    testWidgets('«Ahora»: se guarda en el teléfono con la hora del reloj y muestra el resumen', (
      tester,
    ) async {
      await montar(tester);

      await tocarTerminar(tester);

      expect(local.unica.fin!.isAtSameMomentAs(ahoraDeLaCuenta), isTrue);
      expect(_resumen, findsOneWidget);
    });

    testWidgets('con la hora que ella elige: no se inventa otra', (tester) async {
      await montar(tester);

      await elegirUnaHoraAntes(tester);
      expect(find.textContaining('14:36'), findsOneWidget);
      await tocarTerminar(tester);

      expect(local.unica.fin!.isAtSameMomentAs(DateTime(2026, 10, 23, 14, 36)), isTrue);
    });

    testWidgets('«Volver al inicio» deja la pantalla de la cuenta, ya sin «Terminar jornada»', (
      tester,
    ) async {
      await montar(tester);
      await tocarTerminar(tester);

      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(_seccion, findsNothing);
      expect(_resumen, findsNothing);
    });

    testWidgets(
      'lo cerrado queda en la cola del motor: la jornada cerrada se guarda como siempre',
      (tester) async {
        await montar(tester);
        await tocarTerminar(tester);

        expect(local.jornadas, hasLength(1));
        expect(local.unica.estaAbierta, isFalse);
        expect(local.cierres, 1);
      },
    );
  });

  group('casos límite del cierre', () {
    testWidgets('doble toque: se cierra una sola vez', (tester) async {
      await montar(tester);
      await tester.ensureVisible(_boton);

      await tester.tap(_boton);
      await tester.tap(_boton);
      await tester.pumpAndSettle();

      expect(local.cierres, 1);
      expect(_resumen, findsOneWidget);
    });

    testWidgets('mientras guarda: dice «Terminando…», el botón y la hora quedan apagados', (
      tester,
    ) async {
      final cierre = local.demoraFinalizar = Completer<void>();
      await montar(tester);
      await tester.ensureVisible(_boton);

      await tester.tap(_boton);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Terminando…'), findsOneWidget);
      expect(alTocar(tester), isNull);
      expect(tester.widget<InkWell>(_filaFin).onTap, isNull);
      // Un segundo toque con el cierre en vuelo no llega al almacenamiento.
      await tester.tap(_boton, warnIfMissed: false);
      await tester.pump();
      expect(local.cierres, 1);

      cierre.complete();
      await tester.pumpAndSettle();

      expect(local.unica.fin!.isAtSameMomentAs(ahoraDeLaCuenta), isTrue);
      expect(find.text('Terminando…'), findsNothing);
    });

    testWidgets('si falla el guardado: dice qué pasó y qué hacer, y el botón vuelve a responder', (
      tester,
    ) async {
      local.errorAlFinalizar = StateError('disco lleno');
      await montar(tester);

      await tocarTerminar(tester);

      expect(find.text(_textoErrorGuardar), findsOneWidget);
      expect(find.text('Terminando…'), findsNothing);
      expect(alTocar(tester), isNotNull);
      expect(local.unica.estaAbierta, isTrue);

      // Reintenta y esta vez sale bien: nada quedó trabado.
      local.errorAlFinalizar = null;
      await tocarTerminar(tester);

      expect(local.unica.estaAbierta, isFalse);
      expect(_resumen, findsOneWidget);
    });

    testWidgets('elegir otra hora después de la falla borra el aviso', (tester) async {
      local.errorAlFinalizar = StateError('disco lleno');
      await montar(tester);
      await tocarTerminar(tester);
      expect(_errorFin, findsOneWidget);

      await elegirUnaHoraAntes(tester);

      expect(_errorFin, findsNothing);
    });

    testWidgets('abrir Configuración y volver: la sección sigue y el botón responde', (
      tester,
    ) async {
      await montar(tester);
      await tester.tap(find.byKey(const Key('espera_ir_a_configuracion')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_boton, findsOneWidget);
      expect(alTocar(tester), isNotNull);
    });

    testWidgets('la jornada quedó abierta de un día anterior: pide «¿A qué hora terminaste?»', (
      tester,
    ) async {
      local = LocalDeJornada([jornadaAbiertaDesde(DateTime(2026, 10, 22, 22))]);
      await montar(tester);
      // El selector de «Cambiar ›» no corresponde: el caso de uso pide la pantalla de corrección.
      expect(tester.widget<InkWell>(_filaFin).onTap, isNull);

      await tocarTerminar(tester);

      expect(find.byKey(const Key('corregir_jornada_mensaje')), findsOneWidget);
      expect(local.unica.estaAbierta, isTrue);
    });

    testWidgets('con una entrevista abierta pide su hora de salida y la jornada sigue abierta', (
      tester,
    ) async {
      await montaje.almacen.guardar(entrevistaDePrueba());
      await montar(tester);

      await tocarTerminar(tester);

      expect(find.text('Terminó la entrevista'), findsOneWidget);
      expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
      expect(local.unica.estaAbierta, isTrue);

      // La cierra sin elegir: ni la entrevista ni la jornada se pierden, y el botón responde.
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(local.unica.estaAbierta, isTrue);
      expect(montaje.almacen.guardadas, hasLength(1));
      expect(alTocar(tester), isNotNull);
    });
  });
}
