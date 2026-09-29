// QA de la vista 12 (#221, HU-AUTH-002): verificación de email. Complementa a
// `verificacion_email_page_test.dart` con los tamaños de referencia (360x640 y 412x915) a texto
// 1.0 y 2.0, las entradas del campo de correo, los avisos de error y la navegación.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';

AuthRemoteDataSourceEnMemoria _remoto() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: 'Secreto123'});

/// La página sobre una pantalla inicial, para poder probar "volver".
Future<void> _montar(
  WidgetTester tester,
  AuthRemoteDataSourceEnMemoria remote, {
  String email = _correo,
  String? password = 'Secreto123',
  EstadoVerificacionEmail estado = EstadoVerificacionEmail.pendiente,
  double escala = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('abrir'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VerificacionEmailPage(
                    email: email,
                    password: password,
                    estadoInicial: estado,
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await tester.pumpAndSettle();
}

void _pantalla(WidgetTester tester, Size tamanio) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
  const estados = [
    'pendiente',
    'reenviado',
    'sin conexión al reenviar',
    'límite de reenvíos',
    'expirado con correo',
    'expirado sin correo',
    'error de correo',
    'verificado',
  ];

  Future<void> preparar(WidgetTester tester, String estado, double escala, Size tam) async {
    final remote = _remoto();
    switch (estado) {
      case 'sin conexión al reenviar':
        remote.simularSinConexion = true;
      case 'límite de reenvíos':
        remote.fallaAlReenviar = const ServidorException(
          mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
        );
    }
    await _montar(
      tester,
      remote,
      email: estado.endsWith('sin correo') || estado == 'error de correo' ? '' : _correo,
      password: estado.startsWith('expirado') ? null : 'Secreto123',
      estado: switch (estado) {
        'expirado con correo' || 'expirado sin correo' => EstadoVerificacionEmail.expirado,
        'verificado' => EstadoVerificacionEmail.verificado,
        _ => EstadoVerificacionEmail.pendiente,
      },
      escala: escala,
    );
    if (estado == 'reenviado' ||
        estado == 'sin conexión al reenviar' ||
        estado == 'límite de reenvíos') {
      await _tocar(tester, 'verificacion_email_reenviar');
    }
    if (estado == 'error de correo') {
      await _tocar(tester, 'verificacion_email_reenviar');
    }
  }

  group('QA #221 — tamaños de referencia, texto 1.0 y 2.0', () {
    for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in estados) {
          testWidgets('$estado en $nombre, texto $escala: sin overflow y accesible', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            _pantalla(tester, tam);
            await preparar(tester, estado, escala, tam);

            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('QA #221 — campo de correo (enlace sin contexto)', () {
    Future<void> reenviarCon(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), texto);
      await tester.pump();
      await _tocar(tester, 'verificacion_email_reenviar');
    }

    for (final (entrada, mensaje) in [
      ('', 'Ingresá tu email'),
      ('     ', 'Ingresá tu email'),
      ('lucia', 'El email no es válido'),
      ('lucia@', 'El email no es válido'),
      ('lucia@correo', 'El email no es válido'),
      ('lu cia@correo.com', 'El email no es válido'),
      ('😀@😀.com', null),
      ('${'a' * 300}@correo.com', null),
    ]) {
      testWidgets('"${entrada.length > 20 ? '${entrada.substring(0, 20)}…' : entrada}": '
          '${mensaje ?? 'no rompe la pantalla'}', (tester) async {
        _pantalla(tester, const Size(390, 844));
        final remote = _remoto();
        await _montar(
          tester,
          remote,
          email: '',
          password: null,
          estado: EstadoVerificacionEmail.expirado,
        );
        await reenviarCon(tester, entrada);

        expect(tester.takeException(), isNull);
        if (mensaje != null) {
          expect(find.text(mensaje), findsOneWidget);
          expect(remote.reenviosPorEmail, isEmpty);
          // Lo tipeado no se pierde tras el error.
          final campo = tester.widget<TextField>(find.byKey(const Key('verificacion_email_campo')));
          expect(campo.controller!.text, entrada);
        }
      });
    }

    testWidgets('un correo válido con mayúsculas y espacios se reenvía normalizado', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final remote = _remoto();
      await _montar(
        tester,
        remote,
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await reenviarCon(tester, '  Lucia.Silva@Correo.com ');

      expect(remote.reenviosPorEmail.keys, ['lucia.silva@correo.com']);
    });

    testWidgets('el aviso del campo se va cuando el usuario empieza a corregir', (tester) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(
        tester,
        _remoto(),
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await reenviarCon(tester, 'lucia');
      expect(find.text('El email no es válido'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), 'lucia@correo.com');
      await tester.pump();

      expect(find.text('El email no es válido'), findsNothing);
    });
  });

  group('QA #221 — avisos de error', () {
    testWidgets('"Ya verifiqué mi email" sin conexión dice "Necesitás conexión para ..."', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      final remote = _remoto()..simularSinConexion = true;
      await _montar(tester, remote);
      await _tocar(tester, 'verificacion_email_ya_verifique');

      expect(find.textContaining('Necesitás conexión para'), findsOneWidget);
    });

    testWidgets('un error del servidor al reenviar dice qué hacer', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final remote = _remoto()..fallaAlReenviar = const ServidorException(status: 500);
      await _montar(tester, remote);
      await _tocar(tester, 'verificacion_email_reenviar');

      final aviso = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('verificacion_email_error_general')),
          matching: find.byType(Text),
        ),
      );
      expect(aviso.data, matches(RegExp('Prob|Reintent|volv|intent', caseSensitive: false)));
    });

    testWidgets('un fallo al reenviar deja el botón habilitado para reintentar', (tester) async {
      _pantalla(tester, const Size(390, 844));
      final remote = _remoto()..simularSinConexion = true;
      await _montar(tester, remote);
      await _tocar(tester, 'verificacion_email_reenviar');
      expect(
        find.text('Necesitás conexión para reenviar el email. Conectate y probá de nuevo.'),
        findsOneWidget,
      );

      remote.simularSinConexion = false;
      await _tocar(tester, 'verificacion_email_reenviar');

      expect(remote.reenviosPorEmail[_correo], 1);
      expect(find.byKey(const Key('verificacion_email_error_general')), findsNothing);
    });
  });

  group('QA #221 — reflow a 200 %', () {
    testWidgets('la etiqueta de "Ya verifiqué mi email" no queda recortada por el botón', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640));
      await _montar(tester, _remoto(), escala: 2);
      final boton = tester.getRect(find.byKey(const Key('verificacion_email_ya_verifique')));
      final texto = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('verificacion_email_ya_verifique')),
          matching: find.byType(Text),
        ),
      );
      final radio = boton.height / 2;
      final centro = Offset(boton.left + radio, boton.center.dy);
      for (final esquina in [texto.topLeft, texto.bottomLeft]) {
        if (esquina.dx < boton.left + radio) {
          expect((esquina - centro).distance, lessThanOrEqualTo(radio));
        }
      }
    });
  });

  group('QA #221 — navegación', () {
    testWidgets('"Volver al login" y el atrás del sistema vuelven a la pantalla anterior', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _remoto());
      await _tocar(tester, 'verificacion_email_volver_login');
      expect(find.byKey(const Key('abrir')), findsOneWidget);

      await tester.tap(find.byKey(const Key('abrir')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    testWidgets('el enlace vencido no exige volver a iniciar sesión: ofrece reenviar', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _remoto(), password: null, estado: EstadoVerificacionEmail.expirado);

      expect(find.text('El enlace expiró'), findsOneWidget);
      expect(find.text('Reenviar email de verificación'), findsOneWidget);
    });

    testWidgets('verificado: el texto literal de la HU y "Continuar" vuelve al inicio', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844));
      await _montar(tester, _remoto(), estado: EstadoVerificacionEmail.verificado);

      expect(
        find.text('Email verificado. Esperá la asignación de tu coordinador.'),
        findsOneWidget,
      );
      await _tocar(tester, 'verificacion_email_continuar');
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });
  });
}
