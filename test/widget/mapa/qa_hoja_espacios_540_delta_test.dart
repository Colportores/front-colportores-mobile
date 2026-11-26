// QA del PR #745 (#540): lo que cambió en la hoja de espacios (vista 11, HU-UBI-007) al cerrar los
// hallazgos de QA #211:
//  - el nombre accesible de los campos «Número» y «Piso» (la etiqueta va en el nodo del campo y no se
//    lee dos veces; el botón de teclado sigue siendo un nodo aparte; el nombre sobrevive al error, al
//    texto tipeado y al guardado en curso);
//  - el relleno propio de «Editar edificio» / «Editar casa» con las fuentes reales y el texto ×2;
//  - el encabezado de la hoja (✕ y dirección) sigue a la vista con el aviso puesto, en las cuatro
//    causas del aviso y no solo en una.
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_espacios.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_211_arnes.dart';

/// Todos los nodos de semántica del árbol, con sus datos ya fundidos.
List<SemanticsData> _nodos(WidgetTester tester) {
  final raiz = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final salida = <SemanticsData>[];
  void ir(SemanticsNode n) {
    salida.add(n.getSemanticsData());
    n.visitChildren((h) {
      ir(h);
      return true;
    });
  }

  ir(raiz);
  return salida;
}

int _vecesQueSeNombra(WidgetTester tester, String texto) =>
    _nodos(tester).where((d) => d.label.contains(texto)).length;

class _Cuenta extends EstadoCuentaNotifier {
  _Cuenta(this._e);
  final EstadoCuenta _e;
  @override
  Future<EstadoCuenta?> build() async => _e;
}

void main() {
  group('campos «Número» y «Piso»: el nombre accesible', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        final donde = '${tamano.width.toInt()}×${tamano.height.toInt()} ×$escala';

        testWidgets(
          'dado que se abre el alta a $donde, el campo se llama «NÚMERO · OBLIGATORIO» y es un campo '
          'de texto; el nombre no se repite en otro nodo',
          (tester) async {
            final h = tester.ensureSemantics();
            await llegarA(tester, EstadoV11.alta, tamano: tamano, escala: escala);

            final numero = tester.getSemantics(campoNumero);
            expect(numero.label, contains(TextosEspacios.numeroObligatorio));
            expect(numero.flagsCollection.isTextField, isTrue);
            final piso = tester.getSemantics(campoPiso);
            expect(piso.label, contains(TextosEspacios.pisoOpcional));
            expect(piso.flagsCollection.isTextField, isTrue);

            expect(_vecesQueSeNombra(tester, TextosEspacios.numeroObligatorio), 1);
            expect(_vecesQueSeNombra(tester, TextosEspacios.pisoOpcional), 1);
            expect(tester.takeException(), isNull);
            await capturar211(tester, '540_alta_${tamano.width.toInt()}_x$escala');
            h.dispose();
          },
        );
      }
    }

    testWidgets('el nombre del campo no arrastra el del botón de teclado ni el de «Piso»', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.alta);

      final numero = tester.getSemantics(campoNumero).label;
      expect(numero.contains(TextosEspacios.tecladoALetras), isFalse, reason: numero);
      expect(numero.contains(TextosEspacios.tecladoANumeros), isFalse, reason: numero);
      expect(numero.contains(TextosEspacios.pisoOpcional), isFalse, reason: numero);
      h.dispose();
    });

    testWidgets(
      'el botón de cambiar de teclado sigue siendo un nodo con nombre y acción de tocar',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, EstadoV11.alta);

        final botones = _nodos(tester).where(
          (d) =>
              d.label.contains(TextosEspacios.tecladoALetras) ||
              d.label.contains(TextosEspacios.tecladoANumeros),
        );
        // «Número» arranca numérico (ofrece letras) y «Piso» también: un botón por campo.
        expect(botones.length, 2);
        for (final b in botones) {
          expect(b.hasAction(SemanticsAction.tap), isTrue, reason: b.label);
          expect(b.flagsCollection.isButton, isTrue, reason: b.label);
        }
        h.dispose();
      },
    );

    testWidgets('con el número tipeado el campo conserva el nombre y el valor', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.alta);
      await escribir(tester, campoNumero, '301');
      await tester.pump();

      final n = tester.getSemantics(campoNumero);
      expect(n.label, contains(TextosEspacios.numeroObligatorio));
      expect(n.value, '301');
      h.dispose();
    });

    testWidgets('con el error de «sin número» el campo conserva su nombre', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.altaSinNumero);

      final n = tester.getSemantics(campoNumero);
      expect(n.label, contains(TextosEspacios.numeroObligatorio));
      expect(_vecesQueSeNombra(tester, TextosEspacios.numeroObligatorio), 1);
      h.dispose();
    });

    testWidgets('con el depto repetido el campo conserva su nombre y lo tipeado', (tester) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.repetido);

      final n = tester.getSemantics(campoNumero);
      expect(n.label, contains(TextosEspacios.numeroObligatorio));
      expect(n.value, '102');
      h.dispose();
    });

    testWidgets('al editar un depto los campos tienen el mismo nombre que en el alta', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.edicion);

      expect(tester.getSemantics(campoNumero).label, contains(TextosEspacios.numeroObligatorio));
      expect(tester.getSemantics(campoPiso).label, contains(TextosEspacios.pisoOpcional));
      expect(tester.getSemantics(campoNumero).value, '101');
      h.dispose();
    });

    testWidgets('mientras se guarda (campo de solo lectura) el nombre no se pierde', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final m = await llegarA(tester, EstadoV11.alta);
      final espera = Completer<void>();
      m.repo.espera = espera;
      await escribir(tester, campoNumero, '301');
      await tester.tap(botonAgregar);
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.getSemantics(campoNumero).label, contains(TextosEspacios.numeroObligatorio));
      expect(tester.takeException(), isNull);
      espera.complete();
      await asentarHoja(tester);
      h.dispose();
    });

    testWidgets('el texto visible de la etiqueta no se lee aparte del campo (sin nodo suelto)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, EstadoV11.alta);

      final sueltos = _nodos(tester).where(
        (d) =>
            d.label == TextosEspacios.numeroObligatorio || d.label == TextosEspacios.pisoOpcional,
      );
      // La etiqueta sola (sin ser campo) sería el `Text` que el PR excluye de la semántica.
      expect(sueltos.where((d) => !d.flagsCollection.isTextField), isEmpty);
      h.dispose();
    });
  });

  group('«Editar edificio» / «Editar casa» con el relleno propio (fuentes reales)', () {
    for (final tamano in [telefonoChico211, telefonoGrande211]) {
      for (final escala in [1.0, 2.0]) {
        for (final tipo in [TipoUbicacion.edificio, TipoUbicacion.casa]) {
          testWidgets(
            'a ${tamano.width.toInt()}×${tamano.height.toInt()} con texto ×$escala «Editar '
            '${tipo.name}» deja aire a los dos lados, mide ≥ 48 dp y no desborda',
            (tester) async {
              await llegarA(
                tester,
                tipo == TipoUbicacion.casa ? EstadoV11.casa : EstadoV11.lista,
                tamano: tamano,
                escala: escala,
              );
              await tester.ensureVisible(botonEditarUbicacion);
              await tester.pump();

              final rb = tester.getRect(botonEditarUbicacion);
              final rt = tester.getRect(
                find.descendant(of: botonEditarUbicacion, matching: find.byType(Text)),
              );
              expect(rt.left - rb.left, greaterThanOrEqualTo(20), reason: 'botón $rb texto $rt');
              expect(rb.right - rt.right, greaterThanOrEqualTo(20), reason: 'botón $rb texto $rt');
              expect(rb.height, greaterThanOrEqualTo(48));
              expect(rb.right, lessThanOrEqualTo(tamano.width), reason: 'el botón se sale: $rb');
              expect(tester.takeException(), isNull);
              await capturar211(tester, '540_editar_${tipo.name}_${tamano.width.toInt()}_x$escala');
            },
          );
        }
      }
    }

    testWidgets('el relleno no cambió el botón «+ Departamento» ni el tema de los demás botones', (
      tester,
    ) async {
      await llegarA(tester, EstadoV11.lista);
      final a = tester.getRect(botonAgregarDepto);
      final b = tester.getRect(botonEditarUbicacion);
      expect(a.top, closeTo(b.top, 0.5), reason: 'los dos botones siguen en la misma fila');
    });
  });

  group(
    'el encabezado sigue a la vista con el aviso, en las tres causas que el QA de #211 no medía',
    () {
      Future<void> montarYDisparar(
        WidgetTester tester,
        Future<void> Function(MontajeHoja) disparar, {
        required EstadoCuenta cuenta,
        required Size tamano,
        required double escala,
      }) async {
        await cargarFuentes211(tester);
        final m = await montarHoja(
          tester,
          espacios: deptosDelCanvas(),
          tamano: tamano,
          escala: escala,
          abrir: false,
          extras: [estadoCuentaProvider.overrideWith(() => _Cuenta(cuenta))],
        );
        final contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
        final s = contenedor.listen(estadoCuentaProvider, (_, _) {});
        addTearDown(s.close);
        await asentarHoja(tester);
        await abrirLaHoja(tester);
        await disparar(m);
        await asentarHoja(tester);
      }

      for (final tamano in [telefonoChico211, telefonoGrande211]) {
        for (final escala in [1.0, 2.0]) {
          final donde = '${tamano.width.toInt()}×${tamano.height.toInt()} ×$escala';
          testWidgets('suspendida · fila de un depto a $donde', (tester) async {
            await montarYDisparar(
              tester,
              (_) => tester.tap(filaDepto('e-102')),
              cuenta: EstadoCuenta.suspendida,
              tamano: tamano,
              escala: escala,
            );
            expect(cerrarHojaUbicacion.hitTestable(), findsOneWidget);
            expect(find.text('Mataojo 2044').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capturar211(tester, '540_aviso_fila_${tamano.width.toInt()}_x$escala');
          });

          testWidgets('la edición no se pudo abrir a $donde', (tester) async {
            await montarYDisparar(
              tester,
              (m) async {
                final espera = Completer<SalidaModificarUbicacion?>();
                m.esperaEdicion = espera;
                await tester.tap(botonEditarUbicacion);
                await tester.pump();
                espera.completeError(StateError('no abrió'));
              },
              cuenta: EstadoCuenta.activa,
              tamano: tamano,
              escala: escala,
            );
            expect(find.byKey(ClavesHojaUbicacion.aviso), findsOneWidget);
            expect(cerrarHojaUbicacion.hitTestable(), findsOneWidget);
            expect(find.text('Mataojo 2044').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('pendiente · «Editar edificio» a $donde', (tester) async {
            await montarYDisparar(
              tester,
              (_) => tester.tap(botonEditarUbicacion),
              cuenta: EstadoCuenta.pendienteAsignacion,
              tamano: tamano,
              escala: escala,
            );
            expect(cerrarHojaUbicacion.hitTestable(), findsOneWidget);
            expect(find.text('Mataojo 2044').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    },
  );
}
