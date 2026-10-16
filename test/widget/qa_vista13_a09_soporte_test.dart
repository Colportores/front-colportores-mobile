// QA de verificación de la vista 13 (#222), commit «A09 como el diseño + soporte por WhatsApp»:
// casos límite que `preparacion_db_local_page_test.dart` no cubre. A09 con la sesión restaurada
// (contraseña equivocada, sin conexión, salida), y el aviso de soporte que no debe sobrevivir a un
// reintento.
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_enlace_externo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';

import 'package:colportores_mobile/features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/password_para_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

late DbLocalRepositoryEnMemoria _db;
late AuthRemoteDataSourceEnMemoria _remoto;
late _EnlaceFalso _soporte;

final class _Ajustes implements AbridorAjustesSistema {
  @override
  Future<bool> abrirSeguridad() async => true;
  @override
  Future<bool> abrirAlmacenamiento() async => true;
  @override
  Future<bool> abrirRed() async => true;
}

final class _EnlaceFalso implements AbridorEnlaceExterno {
  final abiertos = <Uri>[];
  bool resultado = true;

  @override
  Future<bool> abrir(Uri enlace) async {
    abiertos.add(enlace);
    return resultado;
  }
}

Finder _k(String key) => find.byKey(Key(key));

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _entrar(WidgetTester tester, {bool restaurada = false}) async {
  _remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password});
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(_remoto),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(_db),
      abridorAjustesSistemaProvider.overrideWithValue(_Ajustes()),
      abridorEnlaceExternoProvider.overrideWithValue(_soporte),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container.read(sesionProvider.notifier).iniciarSesion(email: _email, password: _password);
  if (restaurada) container.read(passwordParaDbLocalProvider).olvidar();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
}

void _interrumpida() {
  final dek = Uint8List.fromList(List<int>.filled(32, 5));
  _db
    ..archivo = true
    ..dekEnAlmacen = dek
    ..envoltorio = (dek: dek, password: _password);
}

void main() {
  setUp(() {
    _db = DbLocalRepositoryEnMemoria();
    _soporte = _EnlaceFalso();
  });

  group('QA vista 13 — A09 con la sesión restaurada', () {
    testWidgets('«Empezar de nuevo» con contraseña equivocada avisa, no toca lo parcial, conserva '
        'lo tipeado y deja reintentar con la correcta', (tester) async {
      _interrumpida();
      await _entrar(tester, restaurada: true);
      await _tocar(tester, 'preparacion_db_empezar_interrumpida');

      await tester.enterText(_k('preparacion_db_password'), 'equivocada');
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
      expect(find.text('equivocada'), findsOneWidget);
      expect(_db.archivo, isTrue, reason: 'sin contraseña válida no se descarta nada');
      expect(_db.llamadas, isNot(contains('descartar')));
      expect(find.byType(InicioPage), findsNothing);

      await tester.enterText(_k('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.byType(InicioPage), findsOneWidget);
    });

    testWidgets('«Empezar de nuevo» sin conexión dice "Necesitás conexión para confirmar tu '
        'contraseña." y no pierde lo parcial', (tester) async {
      _interrumpida();
      await _entrar(tester, restaurada: true);
      await _tocar(tester, 'preparacion_db_empezar_interrumpida');

      _remoto.simularSinConexion = true;
      await tester.enterText(_k('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(find.text('Necesitás conexión para confirmar tu contraseña.'), findsOneWidget);
      expect(_db.archivo, isTrue);
      expect(_db.llamadas, isNot(contains('descartar')));

      _remoto.simularSinConexion = false;
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.byType(InicioPage), findsOneWidget);
    });

    testWidgets(
      'quien no recuerda la contraseña tiene salida desde ese pedido (no queda atrapado)',
      (tester) async {
        _interrumpida();
        await _entrar(tester, restaurada: true);
        await _tocar(tester, 'preparacion_db_empezar_interrumpida');

        expect(find.text(TextosPreparacionDbLocal.olvidePassword), findsOneWidget);
        expect(_k('preparacion_db_cerrar_sesion'), findsOneWidget);
      },
    );
  });

  group('QA vista 13 — aviso de soporte', () {
    testWidgets('el aviso de «no pudimos abrir WhatsApp» no sobrevive a un «Reintentar desde cero» '
        'que vuelve a fallar', (tester) async {
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();
      _soporte.resultado = false;
      await _entrar(tester);
      await _tocar(tester, 'preparacion_db_contactar_soporte');
      expect(_k('preparacion_db_aviso_soporte'), findsOneWidget);

      await _tocar(tester, 'preparacion_db_reintentar');

      expect(
        _k('preparacion_db_aviso_soporte'),
        findsNothing,
        reason: 'es una falla nueva: el aviso viejo ya no corresponde',
      );
    });
  });

  group('QA vista 13 — decisión del 01/10: por qué se pide la contraseña', () {
    const explicacion =
        'La app se cerró mientras preparaba tus datos. Para protegerlos, confirmá tu contraseña.';

    testWidgets('la explicación sigue visible tras una contraseña equivocada y sin conexión', (
      tester,
    ) async {
      _interrumpida();
      await _entrar(tester, restaurada: true);
      await _tocar(tester, 'preparacion_db_empezar_interrumpida');
      expect(find.text(explicacion), findsOneWidget);

      await tester.enterText(_k('preparacion_db_password'), 'equivocada');
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
      expect(find.text(explicacion), findsOneWidget);

      _remoto.simularSinConexion = true;
      await tester.enterText(_k('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.text('Necesitás conexión para confirmar tu contraseña.'), findsOneWidget);
      expect(find.text(explicacion), findsOneWidget);
    });

    testWidgets('sin interrupción previa (base existente sin envoltorio) el texto es el genérico', (
      tester,
    ) async {
      final dek = Uint8List.fromList(List<int>.filled(32, 9));
      _db
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = dek
        ..dekEnAlmacen = dek;
      await _entrar(tester, restaurada: true);

      expect(find.text('Confirmá tu contraseña'), findsOneWidget);
      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
      expect(find.text(explicacion), findsNothing);
    });

    for (final tam in const [Size(360, 640), Size(412, 915)]) {
      testWidgets('el pedido con la explicación a 200 % en ${tam.width.toInt()}x'
          '${tam.height.toInt()}: sin overflow, texto completo y accesible', (tester) async {
        tester.view.physicalSize = tam;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        _interrumpida();
        await _entrar(tester, restaurada: true);
        await _tocar(tester, 'preparacion_db_empezar_interrumpida');

        expect(tester.takeException(), isNull);
        expect(find.text(explicacion), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  });
}
