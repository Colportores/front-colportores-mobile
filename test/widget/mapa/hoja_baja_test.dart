// Vista 09 «Dar de baja y reactivar», parte de la baja (HU-UBI-005, #205): un test por artboard (09·01
// y 09·02), por estado (revisando, error al revisar), por aviso literal de la HU y por caso límite
// (doble toque, falla a mitad, dos acciones seguidas, volver y reentrar, datos límite y texto a 200 %).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_baja.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_baja.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/baja_ubicacion_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

/// El instante de «hoy» de los tests: la baja se escribe con él.
final _hoy = DateTime.utc(2026, 10, 9, 15);

/// La pantalla que abre la hoja y guarda cómo se cerró.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.ubicacion, required this.salidas, this.ofreceIrALaCobranza});

  final Ubicacion ubicacion;
  final List<SalidaHojaBaja?> salidas;
  final bool? ofreceIrALaCobranza;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await mostrarHojaBaja(
              context,
              ubicacion: ubicacion,
              ofreceIrALaCobranza: ofreceIrALaCobranza ?? false,
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

final class _Escenario {
  _Escenario({required this.repo, required this.pendientes});

  final RepoEdicionFalso repo;
  final PendientesFalso pendientes;
  final salidas = <SalidaHojaBaja?>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Escenario> _montar(
  WidgetTester tester, {
  Ubicacion? ubicacion,
  RepoEdicionFalso? repo,
  PendientesFalso? pendientes,
  bool consultorReal = false,
  bool? ofreceIrALaCobranza,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final u = ubicacion ?? ubicacionGuardada();
  final e = _Escenario(
    repo: repo ?? RepoEdicionFalso(u),
    pendientes: pendientes ?? PendientesFalso(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ubicacionRepositoryProvider.overrideWithValue(e.repo),
        relojAltaUbicacionProvider.overrideWithValue(() => _hoy),
        if (!consultorReal) consultorPendientesUbicacionProvider.overrideWithValue(e.pendientes),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(
          ubicacion: u,
          salidas: e.salidas,
          ofreceIrALaCobranza: ofreceIrALaCobranza,
        ),
      ),
    ),
  );
  if (abrir) await _abrir(tester);
  return e;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _titulo => find.text('¿Dar de baja Av. Italia 1234?');
Finder get _boton => find.widgetWithText(FilledButton, TextosBaja.darDeBaja);
Finder get _botonEnCurso => find.widgetWithText(FilledButton, TextosBaja.dandoDeBaja);
Finder get _cancelar => find.widgetWithText(TextButton, TextosBaja.cancelar);

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

Finder _chip(String motivo) => find.text(motivo);
Finder _chipElegido(String motivo) => find.text('✓ $motivo');

const _cobranza = CobranzaPendiente(montoCentavos: 145000, numeroCuota: 2);

void main() {
  group('09·01 · Dar de baja con motivo', () {
    testWidgets('dado que se abre, entonces muestra el título con la dirección, lo que pasa, los '
        'cuatro motivos sin ninguno elegido y «Dar de baja» apagado', (tester) async {
      await _montar(tester);

      expect(_titulo, findsOneWidget);
      expect(
        find.text(
          'Deja de aparecer en el mapa y en la lista. Las visitas y ventas quedan guardadas y la '
          'podés reactivar.',
        ),
        findsOneWidget,
      );
      expect(find.text('MOTIVO · OBLIGATORIO'), findsOneWidget);
      for (final motivo in ['Ya no existe', 'Está deshabitada', 'No quiere visitas', 'Otro']) {
        expect(_chip(motivo), findsOneWidget, reason: motivo);
        expect(_chipElegido(motivo), findsNothing, reason: 'ninguno viene elegido');
      }
      expect(_boton, findsOneWidget);
      expect(_habilitado(tester, _boton), isFalse);
      expect(find.text(TextosBaja.elegiUnMotivo), findsOneWidget);
      expect(_cancelar, findsOneWidget);
      expect(find.text('Revisando la ubicación…'), findsNothing);
    });

    testWidgets(
      'dado un motivo elegido, entonces lleva «✓», «Dar de baja» se habilita y el aviso de '
      'lo que falta desaparece',
      (tester) async {
        await _montar(tester);

        await _tocar(tester, _chip('Ya no existe'));

        expect(_chipElegido('Ya no existe'), findsOneWidget);
        expect(_habilitado(tester, _boton), isTrue);
        expect(find.text(TextosBaja.elegiUnMotivo), findsNothing);
      },
    );

    testWidgets('dado un motivo, cuando toca «Dar de baja», entonces escribe con ese motivo y la '
        'versión que cargó la pantalla, y la hoja se cierra con la ubicación de baja', (
      tester,
    ) async {
      final e = await _montar(tester);

      await _tocar(tester, _chip('Ya no existe'));
      await _tocar(tester, _boton);

      expect(e.repo.bajas, [
        (id: 'ubi-1', baseUpdatedAt: tocadaElUltimoDia, motivo: 'Ya no existe'),
      ]);
      expect(_titulo, findsNothing);
      final salida = e.salidas.single;
      expect(salida, isA<BajaRealizada>());
      expect((salida! as BajaRealizada).ubicacion.estaBorrada, isTrue);
      expect(e.repo.actual!.auditoria.deletedAt, _hoy);
    });

    for (final motivo in ['Está deshabitada', 'No quiere visitas']) {
      testWidgets(
        'dado el motivo «$motivo», cuando da de baja, entonces el repositorio lo recibe',
        (tester) async {
          final e = await _montar(tester);

          await _tocar(tester, _chip(motivo));
          await _tocar(tester, _boton);

          expect(e.repo.bajas.single.motivo, motivo);
        },
      );
    }

    testWidgets('dado «Otro», entonces aparece el campo de texto y el botón se habilita aunque no '
        'escriba nada: el motivo queda como «Otro»', (tester) async {
      final e = await _montar(tester);
      expect(find.byType(TextField), findsNothing);

      await _tocar(tester, _chip('Otro'));

      expect(find.byType(TextField), findsOneWidget);
      expect(_habilitado(tester, _boton), isTrue);
      await _tocar(tester, _boton);
      expect(e.repo.bajas.single.motivo, 'Otro');
    });

    testWidgets(
      'dado «Otro» con un texto, cuando da de baja, entonces el motivo es el texto sin los '
      'espacios de los costados',
      (tester) async {
        final e = await _montar(tester);

        await _tocar(tester, _chip('Otro'));
        await tester.enterText(find.byType(TextField), '  Se mudó a Rivera  ');
        await tester.pump();
        await _tocar(tester, _boton);

        expect(e.repo.bajas.single.motivo, 'Se mudó a Rivera');
      },
    );

    testWidgets('dado «Otro», cuando escribe de más, entonces el campo corta en 120 caracteres', (
      tester,
    ) async {
      final e = await _montar(tester);

      await _tocar(tester, _chip('Otro'));
      await tester.enterText(find.byType(TextField), 'a' * 300);
      await tester.pump();
      await _tocar(tester, _boton);

      expect(e.repo.bajas.single.motivo, 'a' * MotivosBaja.maximoOtro);
    });

    testWidgets('dado un motivo y luego otro antes de enviar, entonces queda uno solo marcado y se '
        'guarda el último (dos acciones seguidas)', (tester) async {
      final e = await _montar(tester);

      await _tocar(tester, _chip('Ya no existe'));
      await _tocar(tester, _chip('Está deshabitada'));

      expect(_chipElegido('Ya no existe'), findsNothing);
      expect(_chipElegido('Está deshabitada'), findsOneWidget);
      await _tocar(tester, _boton);
      expect(e.repo.bajas.single.motivo, 'Está deshabitada');
    });

    testWidgets('dado «Cancelar», entonces cierra sin escribir nada', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, _chip('Ya no existe'));

      await _tocar(tester, _cancelar);

      expect(_titulo, findsNothing);
      expect(e.salidas, [null]);
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets(
      'dado que se cierra con motivo elegido y se vuelve a abrir, entonces empieza de cero '
      'y vuelve a revisar la ubicación',
      (tester) async {
        final e = await _montar(tester);
        await _tocar(tester, _chip('Ya no existe'));
        await _tocar(tester, _cancelar);

        await _abrir(tester);

        expect(_titulo, findsOneWidget);
        expect(_chipElegido('Ya no existe'), findsNothing);
        expect(_habilitado(tester, _boton), isFalse);
        expect(e.pendientes.consultadas, ['ubi-1', 'ubi-1']);
      },
    );

    testWidgets('dado que el consultor de lo pendiente es el de producción (sin visitas, ventas ni '
        'cobranzas en el teléfono), entonces no ofrece la baja a ciegas: avisa que no pudo revisar y '
        'deja reintentar', (tester) async {
      final e = await _montar(tester, consultorReal: true);

      expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_chip('Ya no existe'), findsNothing);
      expect(find.text(TextosBaja.bloqueadaTitulo), findsNothing);
      expect(e.repo.bajas, isEmpty);

      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget, reason: 'sigue sin fuente');
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets('dado que la ubicación ya estaba de baja (un doble toque o el sync llegó primero), '
        'cuando da de baja, entonces cierra como hecha sin escribir de nuevo', (tester) async {
      final yaDeBaja = ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 10, 9, 14));
      final e = await _montar(tester, ubicacion: yaDeBaja);

      await _tocar(tester, _chip('Ya no existe'));
      await _tocar(tester, _boton);

      expect(e.repo.bajas, isEmpty);
      expect(e.salidas.single, isA<BajaRealizada>());
    });
  });

  group('Revisando la ubicación antes de pedir el motivo', () {
    testWidgets(
      'dado que todavía se mira lo pendiente, entonces dice «Revisando la ubicación…», no '
      'ofrece motivos ni «Dar de baja» y deja cancelar',
      (tester) async {
        final pendientes = PendientesFalso()..espera = Completer<void>();
        await _montar(tester, pendientes: pendientes);

        expect(find.text('Revisando la ubicación…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(_chip('Ya no existe'), findsNothing);
        expect(_boton, findsNothing);
        expect(_habilitado(tester, _cancelar), isTrue);

        pendientes.espera!.complete();
        await _asentar(tester);

        expect(find.text('Revisando la ubicación…'), findsNothing);
        expect(_chip('Ya no existe'), findsOneWidget);
      },
    );

    testWidgets('dado que no se pudo mirar lo pendiente, entonces avisa con «Reintentar» y no deja '
        'dar de baja', (tester) async {
      final pendientes = PendientesFalso()..falla = const FailureInesperado();
      await _montar(tester, pendientes: pendientes);

      expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_boton, findsNothing);
      expect(_chip('Ya no existe'), findsNothing);
    });

    testWidgets('dado el aviso de error, cuando toca «Reintentar» y ahora sí se puede, entonces '
        'sigue con el motivo', (tester) async {
      final pendientes = PendientesFalso()..falla = const FailureInesperado();
      await _montar(tester, pendientes: pendientes);

      pendientes.falla = null;
      await _tocar(tester, find.text('Reintentar'));

      expect(find.text(TextosBaja.noPudimosRevisar), findsNothing);
      expect(_chip('Ya no existe'), findsOneWidget);
      expect(pendientes.consultadas, hasLength(2));
    });

    testWidgets(
      'dado el aviso de error, cuando «Reintentar» vuelve a fallar, entonces el aviso y el '
      'botón siguen ahí (nada queda trabado en «Revisando…»)',
      (tester) async {
        final pendientes = PendientesFalso()..falla = const FailureInesperado();
        await _montar(tester, pendientes: pendientes);

        await _tocar(tester, find.text('Reintentar'));

        expect(find.text('Revisando la ubicación…'), findsNothing);
        expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );

    testWidgets(
      'dado que el consultor lanza una excepción, entonces cae en el aviso de error en vez '
      'de quedarse revisando',
      (tester) async {
        final pendientes = PendientesFalso()..lanza = StateError('base cerrada');
        await _montar(tester, pendientes: pendientes);

        expect(find.text('Revisando la ubicación…'), findsNothing);
        expect(find.text(TextosBaja.noPudimosRevisar), findsOneWidget);
      },
    );

    testWidgets(
      'dado que se cierra mientras revisa y la consulta termina después, entonces no pasa '
      'nada',
      (tester) async {
        final pendientes = PendientesFalso()..espera = Completer<void>();
        final e = await _montar(tester, pendientes: pendientes);

        await _tocar(tester, _cancelar);
        pendientes.espera!.complete();
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(e.salidas, [null]);
        expect(e.repo.bajas, isEmpty);
      },
    );
  });

  group('09·02 · No se puede dar de baja', () {
    testWidgets('dado una cobranza pendiente, entonces explica cuánto y qué cuota, sin motivos ni '
        '«Dar de baja»', (tester) async {
      final e = await _montar(
        tester,
        pendientes: PendientesFalso(
          const PendientesUbicacion(cobranzaPendiente: _cobranza, tieneVentas: true),
        ),
      );

      expect(find.text('Todavía no se puede dar de baja'), findsOneWidget);
      expect(
        find.text(
          r'Tiene una cobranza pendiente de $U 1.450 (2.ª cuota). Registrá el cobro antes de '
          'darla de baja.',
        ),
        findsOneWidget,
      );
      expect(_chip('Ya no existe'), findsNothing);
      expect(_boton, findsNothing);
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets('dado una cobranza pendiente y una pantalla sin cobranzas, entonces solo ofrece '
        '«Entendido», que cierra sin escribir', (tester) async {
      final e = await _montar(
        tester,
        pendientes: PendientesFalso(const PendientesUbicacion(cobranzaPendiente: _cobranza)),
      );

      expect(find.text('Ir a la cobranza'), findsNothing);
      await _tocar(tester, find.text('Entendido'));

      expect(find.text('Todavía no se puede dar de baja'), findsNothing);
      expect(e.salidas, [null]);
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets('dado una cobranza pendiente y una pantalla que sabe ir a las cobranzas, entonces '
        'ofrece «Ir a la cobranza» y la elige', (tester) async {
      final e = await _montar(
        tester,
        ofreceIrALaCobranza: true,
        pendientes: PendientesFalso(const PendientesUbicacion(cobranzaPendiente: _cobranza)),
      );

      expect(find.text('Entendido'), findsNothing);
      expect(_cancelar, findsOneWidget);
      await _tocar(tester, find.text('Ir a la cobranza'));

      final salida = e.salidas.single;
      expect(salida, isA<IrALaCobranzaElegido>());
      expect((salida! as IrALaCobranzaElegido).ubicacionId, 'ubi-1');
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets(
      'dado una cobranza pendiente con «Ir a la cobranza», cuando cancela, entonces cierra '
      'sin nada',
      (tester) async {
        final e = await _montar(
          tester,
          ofreceIrALaCobranza: true,
          pendientes: PendientesFalso(const PendientesUbicacion(cobranzaPendiente: _cobranza)),
        );

        await _tocar(tester, _cancelar);

        expect(e.salidas, [null]);
      },
    );

    testWidgets('dado una venta de cualquier tipo, entonces el aviso es el literal de la HU y la '
        'única salida es «Entendido»', (tester) async {
      await _montar(
        tester,
        ofreceIrALaCobranza: true,
        pendientes: PendientesFalso(const PendientesUbicacion(tieneVentas: true)),
      );

      expect(
        find.text(
          'No podés dar de baja esta casa porque tiene ventas o visitas de otro colportor. '
          'Si ya no existe, avisale a tu coordinador.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ir a la cobranza'), findsNothing);
      expect(find.text('Entendido'), findsOneWidget);
      expect(_boton, findsNothing);
    });

    testWidgets('dado una visita de otro colportor, entonces el aviso es el mismo de la HU', (
      tester,
    ) async {
      await _montar(
        tester,
        pendientes: PendientesFalso(const PendientesUbicacion(tieneVisitasDeOtros: true)),
      );

      expect(find.textContaining('tiene ventas o visitas de otro colportor'), findsOneWidget);
    });

    testWidgets(
      'dado un bloqueo y además visitas propias pendientes, entonces gana el bloqueo y no '
      'se pide la segunda confirmación',
      (tester) async {
        await _montar(
          tester,
          pendientes: PendientesFalso(
            const PendientesUbicacion(visitasPropiasPendientes: 3, tieneVisitasDeOtros: true),
          ),
        );

        expect(find.text('Todavía no se puede dar de baja'), findsOneWidget);
        expect(find.textContaining('visitas pendientes'), findsNothing);
      },
    );

    testWidgets('dado que entre que abrió la hoja y confirmó llegó una venta, cuando da de baja, '
        'entonces pasa al aviso de bloqueo sin escribir', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, _chip('Ya no existe'));

      e.pendientes.pendientes = const PendientesUbicacion(tieneVentas: true);
      await _tocar(tester, _boton);

      expect(find.text('Todavía no se puede dar de baja'), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
      expect(e.repo.bajas, isEmpty);
      expect(_botonEnCurso, findsNothing);
    });
  });

  group('Segunda confirmación: visitas pendientes propias', () {
    Future<_Escenario> conVisitas(WidgetTester tester, int visitas) async {
      final e = await _montar(
        tester,
        pendientes: PendientesFalso(PendientesUbicacion(visitasPropiasPendientes: visitas)),
      );
      await _tocar(tester, _chip('Ya no existe'));
      await _tocar(tester, _boton);
      return e;
    }

    Finder enElDialogo(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

    testWidgets('dado 2 visitas pendientes propias, cuando da de baja, entonces pregunta con el '
        'literal de la HU y todavía no escribe', (tester) async {
      final e = await conVisitas(tester, 2);

      expect(
        find.text(
          'Esta ubicación tiene 2 visitas pendientes. Si la das de baja, no podrás registrar '
          'nuevas visitas, pero el historial se conserva.',
        ),
        findsOneWidget,
      );
      expect(e.repo.bajas, isEmpty);
    });

    testWidgets('dado 1 visita pendiente, entonces el aviso va en singular', (tester) async {
      await conVisitas(tester, 1);

      expect(find.textContaining('Esta ubicación tiene 1 visita pendiente.'), findsOneWidget);
    });

    testWidgets('dado la pregunta, cuando confirma, entonces da de baja con el motivo elegido', (
      tester,
    ) async {
      final e = await conVisitas(tester, 2);

      await _tocar(tester, enElDialogo(find.text('Dar de baja')));

      expect(e.repo.bajas.single.motivo, 'Ya no existe');
      expect(e.salidas.single, isA<BajaRealizada>());
    });

    testWidgets(
      'dado la pregunta, cuando cancela, entonces no escribe y la hoja sigue con el motivo '
      'elegido y el botón habilitado',
      (tester) async {
        final e = await conVisitas(tester, 2);

        await _tocar(tester, enElDialogo(find.text('Cancelar')));

        expect(find.byType(AlertDialog), findsNothing);
        expect(e.repo.bajas, isEmpty);
        expect(_chipElegido('Ya no existe'), findsOneWidget);
        expect(_habilitado(tester, _boton), isTrue);
        expect(_botonEnCurso, findsNothing);
        expect(e.salidas, isEmpty);
      },
    );

    testWidgets('dado que canceló la pregunta, cuando vuelve a dar de baja y confirma, entonces '
        'escribe una sola vez', (tester) async {
      final e = await conVisitas(tester, 2);
      await _tocar(tester, enElDialogo(find.text('Cancelar')));

      await _tocar(tester, _boton);
      await _tocar(tester, enElDialogo(find.text('Dar de baja')));

      expect(e.repo.bajas, hasLength(1));
    });

    testWidgets('dado la pregunta abierta, cuando el repositorio falla después de confirmar, '
        'entonces el aviso rojo y el botón vuelve a quedar habilitado', (tester) async {
      final e = await conVisitas(tester, 2);
      e.repo.fallaAlDarDeBaja = const FailureInesperado();

      await _tocar(tester, enElDialogo(find.text('Dar de baja')));

      expect(find.text(TextosBaja.noPudimosDarDeBaja), findsOneWidget);
      expect(_habilitado(tester, _boton), isTrue);
    });
  });

  group('Fallas al dar de baja', () {
    testWidgets('dado que la fila cambió desde que se cargó la pantalla, entonces avisa «Esta '
        'ubicación cambió recién…», conserva el motivo y deja reintentar', (tester) async {
      final e = await _montar(tester);
      e.repo.fallaAlDarDeBaja = const FailureBajaCambioReciente();
      await _tocar(tester, _chip('Ya no existe'));

      await _tocar(tester, _boton);

      expect(
        find.text('Esta ubicación cambió recién. Abrila de nuevo y volvé a darla de baja.'),
        findsOneWidget,
      );
      expect(_chipElegido('Ya no existe'), findsOneWidget);
      expect(_habilitado(tester, _boton), isTrue);
      expect(e.salidas, isEmpty, reason: 'la hoja sigue abierta');
    });

    testWidgets(
      'dado una falla a mitad, entonces el botón vuelve a decir «Dar de baja» habilitado, '
      'se puede cancelar y no queda nada «en curso»',
      (tester) async {
        final e = await _montar(tester);
        e.repo.fallaAlDarDeBaja = const FailureInesperado();
        await _tocar(tester, _chip('Ya no existe'));

        await _tocar(tester, _boton);

        expect(find.text('No pudimos dar de baja la ubicación. Probá de nuevo.'), findsOneWidget);
        expect(_botonEnCurso, findsNothing);
        expect(_habilitado(tester, _boton), isTrue);
        expect(_habilitado(tester, _cancelar), isTrue);
        // Los motivos se pueden volver a tocar.
        await _tocar(tester, _chip('No quiere visitas'));
        expect(_chipElegido('No quiere visitas'), findsOneWidget);
      },
    );

    testWidgets(
      'dado una falla, cuando reintenta y ahora sí entra, entonces cierra con la baja hecha '
      'y el aviso desapareció',
      (tester) async {
        final e = await _montar(tester);
        e.repo.fallaAlDarDeBaja = const FailureInesperado();
        await _tocar(tester, _chip('Ya no existe'));
        await _tocar(tester, _boton);

        e.repo.fallaAlDarDeBaja = null;
        await _tocar(tester, _boton);

        expect(e.repo.bajas, hasLength(2));
        expect(e.salidas.single, isA<BajaRealizada>());
        expect(find.text(TextosBaja.noPudimosDarDeBaja), findsNothing);
      },
    );

    testWidgets('dado que el repositorio lanza una excepción, entonces cae en el mismo aviso y no '
        'queda trabado «Dando de baja…»', (tester) async {
      final e = await _montar(tester);
      e.repo.lanzaAlDarDeBaja = StateError('base cerrada');
      await _tocar(tester, _chip('Ya no existe'));

      await _tocar(tester, _boton);

      expect(find.text(TextosBaja.noPudimosDarDeBaja), findsOneWidget);
      expect(_botonEnCurso, findsNothing);
      expect(_habilitado(tester, _boton), isTrue);
    });

    testWidgets('dado un aviso de falla, cuando elige otro motivo, entonces el aviso desaparece', (
      tester,
    ) async {
      final e = await _montar(tester);
      e.repo.fallaAlDarDeBaja = const FailureInesperado();
      await _tocar(tester, _chip('Ya no existe'));
      await _tocar(tester, _boton);

      await _tocar(tester, _chip('Está deshabitada'));

      expect(find.text(TextosBaja.noPudimosDarDeBaja), findsNothing);
    });

    testWidgets('dado que la ubicación ya no está en el teléfono, entonces avisa la falla del '
        'repositorio y deja cerrar', (tester) async {
      final e = await _montar(tester);
      e.repo.fallaAlDarDeBaja = const FailureUbicacionInexistente();
      await _tocar(tester, _chip('Ya no existe'));

      await _tocar(tester, _boton);

      expect(find.text(const FailureUbicacionInexistente().mensaje), findsOneWidget);
      await _tocar(tester, _cancelar);
      expect(_titulo, findsNothing);
    });
  });

  group('Doble toque y envío en curso', () {
    testWidgets(
      'dado dos toques seguidos en «Dar de baja», entonces la baja se pide una sola vez',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoBaja = Completer<void>();
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, _chip('Ya no existe'));

        await tester.tap(_boton);
        await tester.pump();
        await tester.tap(_botonEnCurso, warnIfMissed: false);
        await tester.pump();

        expect(repo.bajas, hasLength(1));
        repo.bloqueoBaja!.complete();
        await _asentar(tester);
        expect(repo.bajas, hasLength(1));
        expect(e.salidas, hasLength(1));
      },
    );

    testWidgets(
      'dado dos toques en el mismo cuadro (antes de que la hoja se redibuje), entonces la baja se '
      'pide una sola vez',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoBaja = Completer<void>();
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, _chip('Ya no existe'));

        await tester.tap(_boton);
        await tester.tap(_boton, warnIfMissed: false);
        await tester.pump();

        expect(repo.bajas, hasLength(1));
        repo.bloqueoBaja!.complete();
        await _asentar(tester);
        expect(repo.bajas, hasLength(1));
        expect(e.salidas, hasLength(1));
      },
    );

    testWidgets(
      'dado que la baja se escribe, entonces dice «Dando de baja…», apagado, y no se puede '
      'cancelar ni cambiar el motivo',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoBaja = Completer<void>();
        await _montar(tester, repo: repo);
        await _tocar(tester, _chip('Ya no existe'));

        await tester.tap(_boton);
        await tester.pump();

        expect(_botonEnCurso, findsOneWidget);
        expect(_habilitado(tester, _botonEnCurso), isFalse);
        expect(_habilitado(tester, _cancelar), isFalse);
        await tester.tap(_chip('Está deshabitada'), warnIfMissed: false);
        await tester.pump();
        expect(_chipElegido('Ya no existe'), findsOneWidget);
        expect(_chipElegido('Está deshabitada'), findsNothing);
        repo.bloqueoBaja!.complete();
        await _asentar(tester);
      },
    );

    testWidgets(
      'dado que la baja se escribe, cuando aprieta atrás o toca afuera, entonces la hoja no '
      'se cierra y el resultado no se pierde',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoBaja = Completer<void>();
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, _chip('Ya no existe'));
        await tester.tap(_boton);
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.tapAt(const Offset(195, 20));
        await _asentar(tester);

        expect(_botonEnCurso, findsOneWidget, reason: 'sigue en curso');
        expect(e.salidas, isEmpty);
        repo.bloqueoBaja!.complete();
        await _asentar(tester);
        expect(e.salidas.single, isA<BajaRealizada>());
      },
    );

    testWidgets('dado que no se escribe nada, cuando aprieta atrás, entonces la hoja se cierra', (
      tester,
    ) async {
      final e = await _montar(tester);

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(_titulo, findsNothing);
      expect(e.salidas, [null]);
    });

    testWidgets(
      'dado que la hoja se cierra mientras la baja se escribe (no debería poder), entonces '
      'cuando termina no pasa nada',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoBaja = Completer<void>();
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, _chip('Ya no existe'));
        await tester.tap(_boton);
        await tester.pump();

        repo.bloqueoBaja!.complete();
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(e.salidas, hasLength(1));
      },
    );
  });

  group('Datos límite, teclado y texto a 200 %', () {
    testWidgets(
      'dado una dirección larguísima, entonces el título la muestra entera y no desborda',
      (tester) async {
        final larga = ubicacionGuardada(
          calle: 'Avenida General Don José Gervasio Artigas y Pablo de María y Presidente Brum',
          numero: '12345 bis apto. 1203 torre norte',
        );
        await _montar(tester, ubicacion: larga, tamano: const Size(360, 640));

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Avenida General Don José Gervasio Artigas'), findsOneWidget);
        expect(_chip('Ya no existe'), findsOneWidget);
      },
    );

    testWidgets('dado una ubicación sin calle ni número, entonces el título usa lo que dice la '
        'dirección de las demás pantallas y no revienta', (tester) async {
      final sinDireccion = ubicacionGuardada(calle: null, numero: null);
      await _montar(tester, ubicacion: sinDireccion);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('¿Dar de baja'), findsOneWidget);
    });

    testWidgets('dado el texto a 200 % en 360×640, entonces el botón se alcanza desplazando y todo '
        'se puede tocar', (tester) async {
      final e = await _montar(tester, escala: 2.0, tamano: const Size(360, 640));

      expect(tester.takeException(), isNull);
      await _tocar(tester, _chip('Otro'));
      await tester.enterText(find.byType(TextField), 'Se mudaron hace un año y la casa está vacía');
      await tester.pump();
      await tester.ensureVisible(_boton);
      await tester.tap(_boton);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(e.repo.bajas.single.motivo, 'Se mudaron hace un año y la casa está vacía');
    });

    testWidgets(
      'dado el teclado abierto al escribir «Otro» en 360×640, entonces nada se corta y el '
      'botón se alcanza',
      (tester) async {
        final e = await _montar(tester, tamano: const Size(360, 640));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await _tocar(tester, _chip('Otro'));

        await tester.enterText(find.byType(TextField), 'Está vacía');
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_boton);
        await tester.tap(_boton);
        await _asentar(tester);
        expect(e.repo.bajas.single.motivo, 'Está vacía');
      },
    );

    for (final (nombre, tamano, escala) in <(String, Size, double)>[
      ('360×640', const Size(360, 640), 1.0),
      ('412×915', const Size(412, 915), 1.0),
      ('360×640 con texto a 200 %', const Size(360, 640), 2.0),
    ]) {
      testWidgets('09·01 cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, tamano: tamano, escala: escala);
        await _tocar(tester, _chip('Ya no existe'));

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('09·02 cumple las guías de accesibilidad en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(
          tester,
          tamano: tamano,
          escala: escala,
          ofreceIrALaCobranza: true,
          pendientes: PendientesFalso(const PendientesUbicacion(cobranzaPendiente: _cobranza)),
        );

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets(
      'dado un lector de pantalla, entonces el motivo elegido se anuncia como marcado y el '
      'título como encabezado',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester);
        await _tocar(tester, _chip('Ya no existe'));

        expect(
          tester.getSemantics(find.bySemanticsLabel('Ya no existe')),
          matchesSemantics(
            label: 'Ya no existe',
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('¿Dar de baja Av. Italia 1234?')),
          matchesSemantics(
            label: '¿Dar de baja Av. Italia 1234?',
            isHeader: true,
            isLiveRegion: true,
          ),
        );
        handle.dispose();
      },
    );
  });
}
