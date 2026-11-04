// QA de «Gestionar espacios dentro de una ubicación» (HU-UBI-007, #212, PR #501), segunda pasada.
// Complementa a `qa_hu_ubi_007_espacios_212_test.dart` (un grupo por escenario de la HU) con lo que ese
// no prueba, contra la DB real en memoria y las pantallas reales:
//  - la regla del «último espacio activo con personas» con datos alrededor: otro edificio con deptos,
//    un depto ya dado de baja, personas dadas de baja;
//  - el número de un depto dado de baja se puede volver a usar;
//  - el recorrido de la baja (aviso con personas, bloqueo, clientes con «Espacio dado de baja») a
//    360×640 y 412×915 con texto ×1,0 y ×2,0, con las fuentes reales: sin overflow ni texto fuera de la
//    pantalla (capturas con `--dart-define=QA_CAPTURAS=true`).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_hu_ubi_007_212_arnes.dart';
import '../../helpers/qa_vista11_211_arnes.dart'
    show cargarFuentes211, capturar211, expectSinTextoFueraDeLosCostados211;
import 'hoja_espacios_arnes.dart'
    show
        avisoRepetido,
        botonAgregar,
        botonAgregarDepto,
        botonDarDeBaja,
        campoNumero,
        campoPiso,
        escribir,
        filaDepto,
        habilitado;

/// Un depto que ya estaba dado de baja cuando se abre la hoja.
Future<void> _deptoDeBaja(String id, String numero, {String ubicacionId = 'ub-1'}) => db212
    .into(db212.espacios)
    .insert(
      EspaciosCompanion.insert(
        id: id,
        ubicacionId: ubicacionId,
        numeroDepto: Value(numero),
        createdAt: t0212,
        updatedAt: t0212,
        createdBy: const Value('col-1'),
        deletedAt: Value(t0212),
      ),
    );

Future<void> _personaDeBaja(String id) => (db212.update(
  db212.personas,
)..where((p) => p.id.equals(id))).write(PersonasCompanion(deletedAt: Value(t0212)));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('regla del último espacio activo con personas, con datos alrededor', () {
    prueba212(
      'los deptos activos de OTRO edificio no cuentan: el único depto con personas de este edificio '
      'sigue bloqueado',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, filaDepto('esp-1'));

        await tocar212(tester, botonDarDeBaja);

        expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsOneWidget);
        expect(find.text(bloqueo212), findsOneWidget);
        expect((await espacio212(tester, 'esp-1')).deletedAt, isNull);
        expect(tel212.deptosEncolados(), isEmpty);
      },
      sembrar: (t) async {
        await edificioConUnDepto212(t);
        await t.ubicacion('ub-2', calle: 'Mercedes', numero: '1500');
        await t.depto('esp-9', '9', ubicacionId: 'ub-2');
        await t.depto('esp-10', '10', ubicacionId: 'ub-2');
      },
    );

    prueba212(
      'un depto ya dado de baja del mismo edificio no cuenta como «otro espacio activo»',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, filaDepto('esp-1'));

        await tocar212(tester, botonDarDeBaja);

        expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsOneWidget);
        expect(find.text(bloqueo212), findsOneWidget);
        expect((await espacio212(tester, 'esp-1')).deletedAt, isNull);
      },
      sembrar: (t) async {
        await edificioConUnDepto212(t);
        await _deptoDeBaja('esp-viejo', '100');
      },
    );

    prueba212(
      'una persona dada de baja no cuenta en el aviso: con 1 viva de 2, dice «1 persona»',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, filaDepto('esp-1'));

        await tocar212(tester, botonDarDeBaja);

        expect(find.text(avisoUnaPersona212), findsOneWidget);
        expect(find.text(avisoDosPersonas212), findsNothing);
      },
      sembrar: (t) async {
        await edificioConDosDeptos212(t);
        await _personaDeBaja('p-jorge');
      },
    );

    prueba212(
      'si todas las personas del depto están dadas de baja, la baja no pide el aviso de personas ni '
      'se bloquea aunque sea el único depto',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, filaDepto('esp-1'));

        await tocar212(tester, botonDarDeBaja);

        expect(find.byKey(ClavesHojaDepto.bajaBloqueada), findsNothing);
        expect(find.text(avisoUnaPersona212), findsNothing);
        expect(find.byKey(ClavesHojaDepto.confirmarBaja), findsOneWidget);
        await tocar212(tester, find.byKey(ClavesHojaDepto.confirmarBaja));
        expect((await espacio212(tester, 'esp-1')).deletedAt, isNotNull);
        expect(tester.takeException(), isNull);
      },
      sembrar: (t) async {
        await edificioConUnDepto212(t);
        await _personaDeBaja('p-ana');
      },
    );
  });

  group('el número de un depto dado de baja', () {
    prueba212(
      'se puede volver a usar en un alta nueva (no es «repetido» contra una baja)',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, botonAgregarDepto);

        await escribir(tester, campoNumero, '100');
        await escribir(tester, campoPiso, '1');
        await tocar212(tester, botonAgregar);

        expect(avisoRepetido, findsNothing);
        final filas = await espacios212(tester);
        expect(filas.where((e) => e.numeroDepto == '100' && e.deletedAt == null), hasLength(1));
        expect(tel212.deptosEncolados(), hasLength(1));
        expect(tester.takeException(), isNull);
      },
      sembrar: (t) async {
        await edificioConUnDepto212(t);
        await _deptoDeBaja('esp-viejo', '100');
      },
    );
  });

  group('recorrido de la baja a 360×640 y 412×915, texto ×1,0 y ×2,0 (fuentes reales)', () {
    const tamanos = [Size(360, 640), Size(412, 915)];
    for (final tamano in tamanos) {
      for (final escala in [1.0, 2.0]) {
        final donde = '${tamano.width.toInt()}×${tamano.height.toInt()} ×$escala';

        prueba212(
          'aviso de la baja con 2 personas a $donde: sin overflow ni texto fuera de la pantalla, y '
          'los botones se alcanzan',
          (tester) async {
            await cargarFuentes211(tester);
            await montar212(tester, tamano: tamano, escala: escala);
            await abrirHoja212(tester);
            await tocar212(tester, filaDepto('esp-1'));
            await tocar212(tester, botonDarDeBaja);

            expect(find.text(avisoDosPersonas212), findsOneWidget);
            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar211(tester, '212_aviso_baja_${tamano.width.toInt()}_x$escala');
            // Los dos botones del aviso se pueden tocar aunque haya que desplazar.
            await tester.ensureVisible(find.byKey(ClavesHojaDepto.confirmarBaja));
            await tester.ensureVisible(find.byKey(ClavesHojaDepto.cancelarBaja));
            expect(tester.takeException(), isNull);
          },
          sembrar: edificioConDosDeptos212,
        );

        prueba212(
          'bloqueo del último espacio a $donde: el texto de la HU entero y «Entendido» a mano',
          (tester) async {
            await cargarFuentes211(tester);
            await montar212(tester, tamano: tamano, escala: escala);
            await abrirHoja212(tester);
            await tocar212(tester, filaDepto('esp-1'));
            await tocar212(tester, botonDarDeBaja);

            expect(find.text(bloqueo212), findsOneWidget);
            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar211(tester, '212_bloqueo_${tamano.width.toInt()}_x$escala');
            await tester.ensureVisible(find.text('Entendido'));
            expect(tester.takeException(), isNull);
          },
          sembrar: edificioConUnDepto212,
        );

        prueba212(
          'clientes del depto dado de baja a $donde: «Espacio dado de baja», sin «+ Agregar cliente»',
          (tester) async {
            await cargarFuentes211(tester);
            await montar212(tester, tamano: tamano, escala: escala);
            await abrirHoja212(tester);
            await tocar212(tester, filaDepto('esp-1'));
            await tocar212(tester, botonDarDeBaja);
            await tocar212(tester, find.byKey(ClavesHojaDepto.confirmarBaja));
            await cerrarHoja212(tester);
            await tocar212(tester, find.text('abrir clientes'));

            expect(find.text(TextosPersonas.espacioDeBaja), findsOneWidget);
            expect(find.text('+ Agregar cliente'), findsNothing);
            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados211(tester, tamano);
            await capturar211(tester, '212_clientes_de_baja_${tamano.width.toInt()}_x$escala');
          },
          sembrar: edificioConDosDeptos212,
        );
      }
    }

    prueba212(
      'el botón «Dar de baja» sigue habilitado tras cerrar el bloqueo (nada trabado)',
      (tester) async {
        await montar212(tester);
        await abrirHoja212(tester);
        await tocar212(tester, filaDepto('esp-1'));
        await tocar212(tester, botonDarDeBaja);
        await tocar212(tester, find.text('Entendido'));

        expect(habilitado(tester, botonDarDeBaja), isTrue);
      },
      sembrar: edificioConUnDepto212,
    );
  });
}
