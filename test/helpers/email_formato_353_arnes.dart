// Arnés de los tests del formato del email (#353): las cuatro pantallas que lo validan (login,
// registro, reenvío de la verificación y recuperación de contraseña) montadas igual, para mandarles
// un email y ver qué dicen y si algo salió al servidor.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acceso_qa_arnes.dart';
import 'db_local_repository_en_memoria.dart';
import 'qa_vista14_351_arnes.dart';

const textoIncompletoDeLasTres = 'El email no es válido';

/// Una pantalla armada para el test: cómo mandarle un email y cuántas veces salió al servidor.
final class ArmadaEmail {
  const ArmadaEmail({required this.enviar, required this.salidas, required this.botonHabilitado});

  /// Escribe [email] en el campo y toca el botón de la pantalla.
  final Future<void> Function(String email) enviar;

  /// Cuántas veces la pantalla le pidió algo al servidor.
  final int Function() salidas;

  /// Si el botón de la pantalla sigue habilitado (un aviso de campo no lo apaga).
  final bool Function() botonHabilitado;
}

final class PantallaEmail {
  const PantallaEmail(this.nombre, this.textoIncompleto, this.armar);

  final String nombre;

  /// El texto de esta pantalla para un email incompleto (el que no cambia con #353).
  final String textoIncompleto;

  final Future<ArmadaEmail> Function(WidgetTester tester, {Size? tamano, double escala}) armar;
}

Future<ArmadaEmail> _armarLogin(WidgetTester tester, {Size? tamano, double escala = 1}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = RemotoQueFalla();
  await montarAcceso(tester, home: const LoginPage(), remoto: remoto, escala: escala);
  await tester.pumpAndSettle();
  FilledButton boton() => tester.widget<FilledButton>(find.byKey(const Key('login_enviar')));
  return ArmadaEmail(
    enviar: (email) async {
      await tester.enterText(find.byKey(const Key('login_email')), email);
      await tester.enterText(find.byKey(const Key('login_password')), claveAna);
      await tester.ensureVisible(find.byKey(const Key('login_enviar')));
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();
    },
    salidas: () => remoto.llamadasIniciarSesion,
    botonHabilitado: () => boton().onPressed != null,
  );
}

Future<ArmadaEmail> _armarRegistro(WidgetTester tester, {Size? tamano, double escala = 1}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = RemotoQueFalla();
  // Como en la app: el registro se abre desde el login, así un envío que sale bien tiene a dónde ir.
  await montarAcceso(tester, home: const LoginPage(), remoto: remoto, escala: escala);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('login_ir_a_registro')));
  await tester.tap(find.byKey(const Key('login_ir_a_registro')));
  await tester.pumpAndSettle();
  assert(find.byType(RegistroPage).evaluate().isNotEmpty, 'el registro tiene que estar abierto');

  Future<void> escribir(String key, String texto) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.enterText(find.byKey(Key(key)), texto);
  }

  Future<void> marcar(String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  var completo = false;
  return ArmadaEmail(
    enviar: (email) async {
      await escribir('registro_email', email);
      if (!completo) {
        await escribir('registro_nombre', 'Lucía');
        await escribir('registro_apellido', 'Silva');
        await escribir('registro_cedula', '4.812.309-2');
        await escribir('registro_password', 'Secreto123');
        await marcar('registro_terminos');
        await marcar('registro_trade_off');
        completo = true;
      }
      await marcar('registro_continuar');
      await tester.pumpAndSettle();
    },
    salidas: () => remoto.llamadasRegistrar,
    botonHabilitado: () {
      final boton = find.byKey(const Key('registro_continuar'));
      return boton.evaluate().isEmpty || tester.widget<FilledButton>(boton).onPressed != null;
    },
  );
}

Future<ArmadaEmail> _armarVerificacion(
  WidgetTester tester, {
  Size? tamano,
  double escala = 1,
}) async {
  if (tamano != null) fijarPantalla(tester, tamano);
  final remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {});
  // El enlace llegó sin contexto: la pantalla no sabe el correo y lo pide en el campo.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const VerificacionEmailPage(
          email: '',
          password: null,
          estadoInicial: EstadoVerificacionEmail.expirado,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  const boton = Key('verificacion_email_reenviar');
  return ArmadaEmail(
    enviar: (email) async {
      await tester.enterText(find.byKey(const Key('verificacion_email_campo')), email);
      await tester.pump();
      await tester.ensureVisible(find.byKey(boton));
      await tester.tap(find.byKey(boton));
      await tester.pumpAndSettle();
    },
    salidas: () => remoto.reenviosPorEmail.values.fold(0, (a, b) => a + b),
    botonHabilitado: () => tester.widget<FilledButton>(find.byKey(boton)).onPressed != null,
  );
}

Future<ArmadaEmail> _armarRecuperacion(
  WidgetTester tester, {
  Size? tamano,
  double escala = 1,
}) async {
  final remoto = remotoQa();
  await montarQa(tester, remote: remoto, tamano: tamano ?? const Size(390, 844), texto: escala);
  return ArmadaEmail(
    enviar: (email) async {
      await escribirQa(tester, email);
      await tocarQa(tester, enviarQa);
      await tester.pumpAndSettle();
    },
    salidas: () => remoto.solicitudesRecuperacionPorEmail.values.fold(0, (a, b) => a + b),
    botonHabilitado: () => habilitadoQa(tester, enviarQa),
  );
}

final pantallasEmail = <PantallaEmail>[
  const PantallaEmail('Login', textoIncompletoDeLasTres, _armarLogin),
  const PantallaEmail('Registro', textoIncompletoDeLasTres, _armarRegistro),
  const PantallaEmail('Reenvío de la verificación', textoIncompletoDeLasTres, _armarVerificacion),
  const PantallaEmail('Recuperación de contraseña', incompletoQa, _armarRecuperacion),
];
