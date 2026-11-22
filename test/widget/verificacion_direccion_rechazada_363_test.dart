// «Verificá tu cuenta» cuando el servidor rechaza la dirección al reenviar (400
// `email_address_invalid`, #363, seguimiento de #354). Con el correo conocido (el del alta o el del
// ingreso, que se muestra en una tarjeta y no se edita) no hay campo donde poner el aviso: va al
// aviso general de la pantalla, con qué hacer («Volvé al login y registrate con otro email»). Sin el
// correo conocido, el campo del email sigue mostrándolo (`email_formato_353_test.dart`).
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/services/validador_email.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart' show fijarPantalla, guiasDeAccesibilidad;
import '../helpers/casos_email.dart';
import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _avisoConocido =
    'No podemos mandar correos a esa dirección. Volvé al login y registrate con otro email.';

final _reenviar = find.byKey(const Key('verificacion_email_reenviar'));
final _volverAlLogin = find.byKey(const Key('verificacion_email_volver_login'));
final _errorGeneral = find.byKey(const Key('verificacion_email_error_general'));
final _mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));
final _campoEmail = find.byKey(const Key('verificacion_email_campo'));

/// La pantalla «Verificá tu cuenta» abierta desde un botón (la de abajo es el login), así «Volver al
/// login» y volver a entrar son los de verdad.
Future<void> _montar(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
  String email = _correo,
  String? password = 'Secreto123',
  EstadoVerificacionEmail estado = EstadoVerificacionEmail.pendiente,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('abrir_verificacion'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VerificacionEmailPage(
                    email: email,
                    password: password,
                    estadoInicial: estado,
                  ),
                ),
              ),
              child: const Text('pantalla de abajo'),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('abrir_verificacion')));
  await tester.pumpAndSettle();
}

Future<void> _tocarReenviar(WidgetTester tester) async {
  await tester.ensureVisible(_reenviar);
  await tester.tap(_reenviar);
  await tester.pumpAndSettle();
}

bool _habilitado(WidgetTester tester, Finder boton) => switch (tester.widget(boton)) {
  FilledButton(:final onPressed) => onPressed != null,
  OutlinedButton(:final onPressed) => onPressed != null,
  TextButton(:final onPressed) => onPressed != null,
  final otro => throw StateError('no es un botón: ${otro.runtimeType}'),
};

AuthRemoteDataSourceEnMemoria _remotoQueRechaza() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {})
      ..fallaAlReenviar = const EmailInvalidoException();

void main() {
  group('Verificá tu cuenta con el correo conocido — el servidor rechaza la dirección (#363)', () {
    testWidgets('dado que el servidor rechaza la dirección, cuando toca «Reenviar email», el aviso '
        'general dice que no se puede mandar y qué hacer', (tester) async {
      await _montar(tester, remote: _remotoQueRechaza());
      await _abrir(tester);

      await _tocarReenviar(tester);

      expect(find.text(_avisoConocido), findsOneWidget);
      expect(
        find.descendant(of: _errorGeneral, matching: find.text(_avisoConocido)),
        findsOneWidget,
        reason: 'va en el aviso general de la pantalla',
      );
      expect(_avisoConocido, ValidadorEmail.avisoDireccionRechazadaSinCampo);
      expect(
        find.text(avisoDireccionRechazada),
        findsNothing,
        reason: 'no hay campo donde ponerlo',
      );
      expect(find.textContaining('email_address_invalid'), findsNothing);
      expect(_campoEmail, findsNothing);
      expect(find.text(_correo), findsOneWidget, reason: 'la tarjeta sigue mostrando el correo');
      expect(_mensajeReenvio, findsNothing, reason: 'no salió ningún correo');
    });

    testWidgets('el aviso se anuncia al lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, remote: _remotoQueRechaza());
      await _abrir(tester);

      await _tocarReenviar(tester);

      expect(tester.getSemantics(_errorGeneral), isSemantics(isLiveRegion: true));
      expect(
        tester.getSemantics(_errorGeneral).label,
        contains(_avisoConocido),
        reason: 'el lector lee el texto entero',
      );
      semantica.dispose();
    });

    testWidgets('después del aviso, «Reenviar» y «Volver al login» siguen habilitados y no corre '
        'ninguna espera', (tester) async {
      await _montar(tester, remote: _remotoQueRechaza());
      await _abrir(tester);

      await _tocarReenviar(tester);

      expect(_habilitado(tester, _reenviar), isTrue);
      expect(_habilitado(tester, _volverAlLogin), isTrue);
      expect(find.textContaining('Reenviar en'), findsNothing);
      expect(find.byKey(const Key('verificacion_email_limite')), findsNothing);
    });

    testWidgets(
      'con el reenvío en vuelo, un segundo toque no pide otra vez y al contestar el aviso '
      'queda una vez y el botón vuelve a estar habilitado',
      (tester) async {
        final remoto = _remotoQueRechaza()..demoraReenvio = Completer<void>();
        await _montar(tester, remote: remoto);
        await _abrir(tester);

        await tester.tap(_reenviar);
        await tester.pump();
        expect(_habilitado(tester, _reenviar), isFalse, reason: 'mientras reenvía se apaga');
        expect(
          _habilitado(tester, _volverAlLogin),
          isFalse,
          reason: 'con el reenvío en vuelo no sale',
        );
        await tester.tap(_reenviar, warnIfMissed: false);
        remoto.demoraReenvio!.complete();
        await tester.pumpAndSettle();

        expect(find.text(_avisoConocido), findsOneWidget);
        expect(_habilitado(tester, _reenviar), isTrue);
        expect(_habilitado(tester, _volverAlLogin), isTrue);
      },
    );

    testWidgets('dos pedidos seguidos: el aviso se vuelve a mostrar y, si el servidor ya acepta la '
        'dirección, desaparece y sale el correo', (tester) async {
      final remoto = _remotoQueRechaza();
      await _montar(tester, remote: remoto);
      await _abrir(tester);

      await _tocarReenviar(tester);
      expect(find.text(_avisoConocido), findsOneWidget);
      await _tocarReenviar(tester);
      expect(find.text(_avisoConocido), findsOneWidget, reason: 'otra vez, no se acumulan dos');

      remoto.fallaAlReenviar = null;
      await _tocarReenviar(tester);

      expect(find.text(_avisoConocido), findsNothing);
      expect(_errorGeneral, findsNothing);
      expect(_mensajeReenvio, findsOneWidget);
      expect(remoto.reenviosPorEmail[_correo], 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'el aviso es del pedido que lo causó: un reenvío sin conexión después lo cambia por '
      'el de sin conexión',
      (tester) async {
        final remoto = _remotoQueRechaza();
        await _montar(tester, remote: remoto);
        await _abrir(tester);
        await _tocarReenviar(tester);
        expect(find.text(_avisoConocido), findsOneWidget);

        remoto.simularSinConexion = true;
        await _tocarReenviar(tester);

        expect(find.text(_avisoConocido), findsNothing);
        expect(
          find.text('Necesitás conexión para reenviar el email. Conectate y probá de nuevo.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('al volver al login y entrar otra vez, la pantalla arranca sin el aviso', (
      tester,
    ) async {
      await _montar(tester, remote: _remotoQueRechaza());
      await _abrir(tester);
      await _tocarReenviar(tester);
      expect(find.text(_avisoConocido), findsOneWidget);

      await tester.ensureVisible(_volverAlLogin);
      await tester.tap(_volverAlLogin);
      await tester.pumpAndSettle();
      expect(find.byType(VerificacionEmailPage), findsNothing, reason: '«Volver al login» sale');
      await _abrir(tester);

      expect(find.byType(VerificacionEmailPage), findsOneWidget);
      expect(find.text(_avisoConocido), findsNothing);
      expect(_errorGeneral, findsNothing);
    });

    testWidgets('con el enlace vencido y sin contraseña (el correo conocido igual), también va al '
        'aviso general', (tester) async {
      await _montar(
        tester,
        remote: _remotoQueRechaza(),
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await _abrir(tester);

      await _tocarReenviar(tester);

      expect(find.text(_avisoConocido), findsOneWidget);
      expect(_campoEmail, findsNothing);
    });

    testWidgets('a 390×844, con el aviso a la vista, la pantalla cumple las guías de '
        'accesibilidad', (tester) async {
      final semantica = tester.ensureSemantics();
      fijarPantalla(tester, const Size(390, 844));
      await _montar(tester, remote: _remotoQueRechaza());
      await _abrir(tester);

      await _tocarReenviar(tester);

      expect(find.text(_avisoConocido), findsOneWidget);
      await guiasDeAccesibilidad(tester);
      semantica.dispose();
    });
  });

  group('Verificá tu cuenta sin el correo conocido — el servidor rechaza la dirección (#363)', () {
    testWidgets('el aviso sigue en el campo del email y no hay aviso general', (tester) async {
      await _montar(
        tester,
        remote: _remotoQueRechaza(),
        email: '',
        password: null,
        estado: EstadoVerificacionEmail.expirado,
      );
      await _abrir(tester);
      await tester.enterText(_campoEmail, 'lucia@gmial.com');
      await tester.pump();

      await _tocarReenviar(tester);

      expect(find.text(avisoDireccionRechazada), findsOneWidget);
      expect(find.text(_avisoConocido), findsNothing);
      expect(_errorGeneral, findsNothing);
      expect(_habilitado(tester, _reenviar), isTrue);
    });
  });
}
