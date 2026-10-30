// La sexta pestaña de la barra, «Cuenta» (decisión de Cristian, 23/10, «Barra o menú»; HU-CTA-001,
// #170): seis pestañas con toque y texto al 200 % sin recorte, la pestaña abre Mi Cuenta y el atrás
// del sistema vuelve a «Hoy».
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

final _ahora = DateTime(2026, 9, 29, 14, 35, 20);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

JornadaModel _abiertaDesde(DateTime inicio) => JornadaModel.fromEntity(
  Jornada(
    id: 'jor-previa',
    colportorId: _sesion.usuarioId,
    inicio: inicio,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: _sesion.usuarioId),
  ),
);

Future<void> _montar(
  WidgetTester tester,
  RepositorioDeCuentaControlable repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(
          JornadaLocalDataSourceEnMemoria(iniciales: [_abiertaDesde(_ahora)]),
        ),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        resumenDeCuentaRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('la barra tiene seis pestañas y «Cuenta» es la sexta', (tester) async {
    await _montar(tester, RepositorioDeCuentaControlable(inicial: resumenDelCanvas));

    expect(PestanaInicio.values.map((p) => p.etiqueta), [
      'Hoy',
      'Mapa',
      'Lista',
      'Agenda',
      'Ventas',
      'Cuenta',
    ]);
    for (final pestana in PestanaInicio.values) {
      expect(find.byKey(Key('inicio_pestana_${pestana.name}')), findsOneWidget);
    }
  });

  testWidgets('dado que abro «Cuenta», veo Mi Cuenta con mis cifras y el atrás del sistema me '
      'devuelve a «Hoy»', (tester) async {
    final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
    await _montar(tester, repo);
    expect(repo.suscripciones, 1, reason: 'se lee al armar la pantalla, no al abrir la pestaña');

    await tester.tap(find.byKey(const Key('inicio_pestana_cuenta')));
    await tester.pumpAndSettle();

    expect(find.text('Mi Cuenta'), findsOneWidget);
    expect(find.text(r'$ 2.400'), findsOneWidget);
    expect(find.text(r'$ 9.700'), findsOneWidget);
    // Al abrir la pestaña se vuelve a leer: «hace una semana» corre con el reloj.
    expect(repo.suscripciones, 2);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Mi Cuenta'), findsNothing);
  });

  testWidgets('ir y volver de «Cuenta» varias veces seguidas no deja nada trabado', (tester) async {
    final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
    await _montar(tester, repo);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('inicio_pestana_cuenta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('inicio_pestana_cuenta')));
    await tester.pumpAndSettle();

    expect(find.text(r'$ 2.400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // La barra sola, hasta los 320 dp de ancho más angostos: «Hoy» no entra en estos tamaños con el texto
  // al 200 % (su fila de la hora, medida aparte con la letra real), pero la barra sí tiene que entrar.
  for (final ancho in [320.0, 360.0, 412.0]) {
    for (final escala in [1.0, 2.0, 3.0]) {
      testWidgets(
        'la barra de seis pestañas a ${ancho.toInt()} dp, texto $escala: sin overflow y con '
        'toque de 48 dp',
        (tester) async {
          final semantica = tester.ensureSemantics();
          tester.view.physicalSize = Size(ancho, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          PestanaInicio? elegida;
          await tester.pumpWidget(
            MaterialApp(
              theme: temaClaro(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                child: child!,
              ),
              home: Scaffold(
                bottomNavigationBar: BarraPestanasInicio(
                  seleccionada: PestanaInicio.cuenta,
                  onSeleccionar: (p) => elegida = p,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final falla = tester.takeException();
          expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
          for (final pestana in PestanaInicio.values) {
            final destino = find.byKey(Key('inicio_pestana_${pestana.name}'));
            expect(tester.getSize(destino).height, greaterThanOrEqualTo(48), reason: pestana.name);
            expect(tester.getSize(destino).width, greaterThanOrEqualTo(ancho / 6 - 1));
          }
          await tester.tap(find.byKey(const Key('inicio_pestana_cuenta')));
          expect(elegida, PestanaInicio.cuenta);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        },
      );
    }
  }

  for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
    for (final escala in [1.0, 2.0]) {
      testWidgets('la pestaña «Cuenta» en ${tam.key}, texto $escala: sin overflow y accesible', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _montar(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
          tamano: tam.value,
          escala: escala,
        );
        await tester.tap(find.byKey(const Key('inicio_pestana_cuenta')));
        await tester.pumpAndSettle();

        expect(find.text('Mi Cuenta'), findsOneWidget);
        final falla = tester.takeException();
        expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
        // Las seis pestañas se tocan: cada una de al menos 48 dp de alto y con su nombre.
        for (final pestana in PestanaInicio.values) {
          final destino = find.byKey(Key('inicio_pestana_${pestana.name}'));
          expect(tester.getSize(destino).height, greaterThanOrEqualTo(48), reason: pestana.name);
          expect(tester.getSize(destino).width, greaterThanOrEqualTo(40), reason: pestana.name);
          expect(find.bySemanticsLabel(RegExp(pestana.etiqueta)), findsWidgets);
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });
    }
  }
}
