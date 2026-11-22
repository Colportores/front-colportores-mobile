// «Verificá tu cuenta» sin el correo conocido (el enlace llegó vencido y la persona escribe su
// dirección): el servidor rechaza la dirección al reenviar (400 `email_address_invalid`) cuando ya
// escribió otra (#371, seguimiento de la revisión de #364). El rechazo es de la dirección que se
// mandó: no va debajo de la que todavía no se probó.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart' show fijarPantalla;
import '../helpers/casos_email.dart';
import '../helpers/db_local_repository_en_memoria.dart';

const _enviada = 'lucia@gmial.com';
const _corregida = 'lucia@gmail.com';

final _campo = find.byKey(const Key('verificacion_email_campo'));
final _reenviar = find.byKey(const Key('verificacion_email_reenviar'));
final _mensajeReenvio = find.byKey(const Key('verificacion_email_mensaje_reenvio'));

/// El servidor rechaza la dirección y contesta cuando el test lo decide (`demoraReenvio`): el
/// reenvío queda en vuelo mientras se escribe en el campo.
AuthRemoteDataSourceEnMemoria _remotoQueRechazaTarde() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {})
      ..fallaAlReenviar = const EmailInvalidoException()
      ..demoraReenvio = Completer<void>();

Future<void> _montar(WidgetTester tester, AuthRemoteDataSourceEnMemoria remoto) async {
  fijarPantalla(tester, const Size(390, 844));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        // El enlace llegó sin contexto: la pantalla no sabe el correo y lo pide en el campo.
        home: const VerificacionEmailPage(
          email: '',
          password: null,
          estadoInicial: EstadoVerificacionEmail.expirado,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String correo) async {
  await tester.enterText(_campo, correo);
  await tester.pump();
}

/// Toca «Reenviar» sin esperar: con `demoraReenvio` puesta, el reenvío queda en vuelo.
Future<void> _tocarReenviar(WidgetTester tester) async {
  await tester.ensureVisible(_reenviar);
  await tester.tap(_reenviar);
  await tester.pump();
}

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_reenviar).onPressed != null;

/// Pide el reenvío de [_enviada] y deja la respuesta en vuelo.
Future<void> _pedirYDejarEnVuelo(WidgetTester tester) async {
  await _escribir(tester, _enviada);
  await _tocarReenviar(tester);
  expect(_habilitado(tester), isFalse, reason: 'el reenvío está en vuelo');
}

void main() {
  group('Verificá tu cuenta sin correo conocido — el rechazo llega con otra dirección escrita '
      '(#371)', () {
    testWidgets('dado que se escribió otra dirección con el reenvío en vuelo, cuando llega el '
        'rechazo de la anterior, el campo nuevo no muestra el aviso', (tester) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);
      await _escribir(tester, _corregida);

      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();

      expect(find.text(avisoDireccionRechazada), findsNothing);
      expect(find.textContaining('email_address_invalid'), findsNothing);
      expect(tester.widget<TextField>(_campo).controller!.text, _corregida);
      expect(_habilitado(tester), isTrue, reason: 'se puede probar la dirección nueva');
      expect(remoto.reenviosPorEmail, isEmpty, reason: 'no salió ningún correo');
    });

    testWidgets('después de ignorar el rechazo viejo, la dirección nueva se prueba y sale', (
      tester,
    ) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);
      await _escribir(tester, _corregida);
      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();
      remoto.fallaAlReenviar = null;

      await _tocarReenviar(tester);
      await tester.pumpAndSettle();

      expect(remoto.reenviosPorEmail, {_corregida: 1});
      expect(_mensajeReenvio, findsOneWidget);
      expect(find.text(avisoDireccionRechazada), findsNothing);
    });

    testWidgets('dado que la dirección nueva también la rechaza el servidor, su propio rechazo sí '
        'se ve debajo de ella', (tester) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);
      await _escribir(tester, _corregida);
      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();
      expect(find.text(avisoDireccionRechazada), findsNothing);

      await _tocarReenviar(tester);
      await tester.pumpAndSettle();

      expect(find.text(avisoDireccionRechazada), findsOneWidget);
    });

    testWidgets('dado que la dirección no cambió, cuando llega el rechazo, el campo lo muestra', (
      tester,
    ) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);

      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();

      expect(find.text(avisoDireccionRechazada), findsOneWidget);
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('dado que solo cambiaron las mayúsculas y los espacios, es la misma dirección y el '
        'rechazo se muestra', (tester) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);
      await _escribir(tester, '  Lucia@Gmial.com ');

      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();

      expect(find.text(avisoDireccionRechazada), findsOneWidget);
    });

    testWidgets('dado que se escribió otra dirección y se volvió a la primera antes de que '
        'contestara, el rechazo es de lo que se ve y se muestra', (tester) async {
      final remoto = _remotoQueRechazaTarde();
      await _montar(tester, remoto);
      await _pedirYDejarEnVuelo(tester);
      await _escribir(tester, _corregida);
      await _escribir(tester, _enviada);

      remoto.demoraReenvio!.complete();
      await tester.pumpAndSettle();

      expect(find.text(avisoDireccionRechazada), findsOneWidget);
    });
  });
}
