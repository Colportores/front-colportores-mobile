// HU-AUTH-009 — preparación de la DB local cifrada después del login (#27). Un test por escenario
// de aceptación con su título literal, los estados de la pantalla y la accesibilidad (tamaño de
// toque, etiquetas y contraste en 390x844; texto al 200 % en 360x740). La app entera con fakes: el
// login publica la sesión y la raíz no muestra la pantalla principal hasta que la DB está abierta.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:colportores_mobile/core/dispositivo/seguridad_dispositivo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/usecases/inicializar_db_local_use_case.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/password_para_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/preparacion_db_local_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

late DbLocalRepositoryEnMemoria _db;

/// El abridor de ajustes, con lo que devolvió cada apertura y una espera para el doble toque.
final class _AbridorFalso implements AbridorAjustesSistema {
  final llamadas = <String>[];
  bool resultado = true;
  bool lanza = false;
  Completer<void>? espera;

  Future<bool> _abrir(String cual) async {
    llamadas.add(cual);
    await espera?.future;
    if (lanza) throw StateError('el abridor falló');
    return resultado;
  }

  @override
  Future<bool> abrirSeguridad() => _abrir('seguridad');

  @override
  Future<bool> abrirAlmacenamiento() => _abrir('almacenamiento');
}

late _AbridorFalso _ajustes;

Finder get _principal => find.byType(InicioPage);
Finder get _preparacion => find.byType(PreparacionDbLocalPage);
Finder _boton(String key) => find.byKey(Key(key));

/// Entra con email y contraseña y monta la app, que prepara la DB local. Con [restaurada], como
/// una sesión que ya estaba al abrir la app: sin la contraseña del login en memoria.
Future<ProviderContainer> _entrar(
  WidgetTester tester, {
  bool esperar = true,
  bool restaurada = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(_db),
      abridorAjustesSistemaProvider.overrideWithValue(_ajustes),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container.read(sesionProvider.notifier).iniciarSesion(email: _email, password: _password);
  if (restaurada) container.read(passwordParaDbLocalProvider).olvidar();

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  if (esperar) await tester.pumpAndSettle();
  return container;
}

bool _botonHabilitado(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_boton(key)).onPressed != null;

/// La pantalla sola en un [estado], sin la app: para los estados que el fake no alcanza (1/3, 3/3).
Future<void> _montarEstado(WidgetTester tester, EstadoPreparacionDbLocal estado) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: temaClaro(),
          home: PreparacionDbLocalPage(estado: estado),
        ),
      ),
    );

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_boton(key));
  await tester.tap(_boton(key));
  await tester.pumpAndSettle();
}

/// Una DB ya creada en el teléfono, con su DEK en [dekEnAlmacen] (o sin ella, si el almacén la
/// perdió) y un envoltorio por contraseña si [conEnvoltorio].
void _dbExistente({required bool dekEnAlmacen, required bool conEnvoltorio}) {
  final dek = Uint8List.fromList(List<int>.filled(32, 9));
  _db
    ..marca = MarcaDbLocal.puesta
    ..archivo = true
    ..claveDelArchivo = dek
    ..dekEnAlmacen = dekEnAlmacen ? dek : null
    ..envoltorio = conEnvoltorio ? (dek: dek, password: _password) : null;
}

void main() {
  setUp(() {
    _db = DbLocalRepositoryEnMemoria();
    _ajustes = _AbridorFalso();
  });

  group('HU-AUTH-009 — criterios de aceptación', () {
    testWidgets('Escenario: Inicialización exitosa — muestra el progreso ("Preparando tu espacio '
        'seguro… 1/3, 2/3, 3/3"), envuelve la DEK con mi contraseña, crea la DB y navega a la '
        'pantalla principal', (tester) async {
      _db.argon2idPendiente = Completer<void>();
      await _entrar(tester, esperar: false);
      await tester.pump();
      await tester.pump();

      expect(_preparacion, findsOneWidget);
      expect(find.text('Preparando tu espacio seguro… 2/3'), findsOneWidget);
      expect(_principal, findsNothing);

      _db.argon2idPendiente!.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
      expect(_db.abierta, isTrue);
      expect(_db.marca, MarcaDbLocal.puesta);
      expect(
        _db.llamadas,
        containsAllInOrder(['bloqueo', 'nivel', 'crearDek', 'envolver', 'abrir', 'marcar']),
      );
    });

    testWidgets('Escenario: Error -equipo sin bloqueo de pantalla — no inicializa la DB y explica '
        'por qué hace falta el bloqueo y cómo configurarlo', (tester) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);

      expect(find.text(const FailureSinBloqueoPantalla().mensaje), findsOneWidget);
      expect(_db.abierta, isFalse);
      expect(_db.llamadas, isNot(contains('crearDek')));

      _db.bloqueoPantalla = true;
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
    });

    testWidgets('Escenario: Keystore por software -consentimiento explícito — si acepta, sigue con '
        'el mismo almacén y registra la elección', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);

      expect(
        find.text(
          'Tu dispositivo tiene almacenamiento menos seguro. Los datos siguen cifrados pero el '
          'nivel de protección es menor.',
        ),
        findsOneWidget,
      );
      expect(find.text('Entiendo el riesgo y quiero continuar'), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));

      // «Continuar» recién se habilita al marcar «Entiendo el riesgo y quiero continuar».
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isFalse);
      await _tocar(tester, 'preparacion_db_entiendo_riesgo');
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isTrue);
      await _tocar(tester, 'preparacion_db_aceptar_riesgo');

      expect(_principal, findsOneWidget);
      expect(_db.consentimiento, isTrue);
    });

    testWidgets('Escenario: Keystore por software -consentimiento explícito — si declina, aborta '
        'con instrucción de cómo usar otro dispositivo', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_cancelar_riesgo');

      expect(find.text(TextosPreparacionDbLocal.otroCelular), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));
      expect(_db.consentimiento, isFalse);

      // Si cambia de idea, vuelve a la advertencia.
      await _tocar(tester, 'preparacion_db_continuar_con_este');
      expect(find.text('Entiendo el riesgo y quiero continuar'), findsOneWidget);
    });

    testWidgets('Escenario: Error -falla al escribir en secure_storage — mensaje accionable y el '
        'dispositivo no queda marcado como inicializado', (tester) async {
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();
      await _entrar(tester);

      expect(
        find.text(
          'No pudimos preparar el almacenamiento seguro. Consultá a soporte antes de reinstalar '
          'la app.',
        ),
        findsOneWidget,
      );
      expect(_db.marca, MarcaDbLocal.ausente);
      expect(_db.dekEnAlmacen, isNull, reason: 'limpia cualquier estado parcial');
    });

    testWidgets('Escenario: Error -sin espacio en disco — aborta limpiamente con "No hay espacio '
        'suficiente para preparar el app" y borra el archivo parcial', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      expect(find.text('No hay espacio suficiente para preparar el app'), findsOneWidget);
      expect(find.text(TextosPreparacionDbLocal.sinEspacioQueHacer), findsOneWidget);
      expect(_db.archivo, isFalse);
      expect(_db.marca, MarcaDbLocal.ausente);
    });

    testWidgets('Escenario: Edge -DB local con un esquema posterior al de la app — pantalla '
        'bloqueante con "Actualizar" y sin "empezar de nuevo"', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
      _db.fallas['abrir'] = const FailureEsquemaPosterior();
      await _entrar(tester);

      expect(
        find.text(
          'Tus datos son de una versión más nueva de la app. Actualizala para seguir usando tus '
          'datos.',
        ),
        findsOneWidget,
      );
      expect(_boton('preparacion_db_empezar_de_nuevo'), findsNothing);
      expect(_boton('preparacion_db_reintentar'), findsNothing);

      await _tocar(tester, 'preparacion_db_actualizar');

      expect(find.text(TextosPreparacionDbLocal.actualizarComo), findsOneWidget);
      expect(_db.archivo, isTrue, reason: 'ni migra ni borra');
    });
  });

  group('Cuenta con contraseña y DB sin envoltorio (revisión del PR #130)', () {
    testWidgets('dada una sesión restaurada sin DB, pide la contraseña antes de crear nada; con la '
        'correcta crea la DB con envoltorio', (tester) async {
      await _entrar(tester, restaurada: true);

      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
      expect(_db.llamadas, isNot(contains('crearDek')));

      await tester.enterText(_boton('preparacion_db_password'), 'equivocada');
      await _tocar(tester, 'preparacion_db_confirmar_password');
      expect(find.text(TextosPreparacionDbLocal.passwordIncorrecta), findsOneWidget);
      expect(_principal, findsNothing);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
    });

    testWidgets('dada una DB existente sin envoltorio, pide la contraseña antes de darla por lista '
        'y la protege sin tocar sus datos', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: false);
      await _entrar(tester, restaurada: true);

      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
      expect(_db.abierta, isFalse);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_confirmar_password');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
      expect(_db.llamadas, isNot(contains('descartar')));
    });

    testWidgets('quien no recuerda la contraseña (entra con Google, por ejemplo) no queda '
        'encerrado: "¿Olvidaste tu contraseña?" lleva a restablecerla con el email de la sesión '
        '(N1)', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: false);
      await _entrar(tester, restaurada: true);
      expect(find.text(TextosPreparacionDbLocal.olvidePassword), findsOneWidget);

      await _tocar(tester, 'preparacion_db_olvide_password');

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      final email = tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email')));
      expect(email.controller!.text, _email);
      expect(_db.llamadas, isNot(contains('descartar')), reason: 'no toca la DB del teléfono');

      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      expect(find.text(const FailurePasswordParaProteger().mensaje), findsOneWidget);
    });
  });

  group('Reintentar (#27)', () {
    testWidgets('dada una falla pasajera del almacén (un Keystore que no respondió a tiempo), '
        '"Reintentar" termina la preparación', (tester) async {
      _db.fallas['nivel'] = const FailureAlmacenSeguro();
      await _entrar(tester);
      expect(_principal, findsNothing);

      _db.fallas.remove('nivel');
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
    });

    testWidgets('el reintento después de liberar espacio también arma el envoltorio con la '
        'contraseña del login', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      _db.fallas.remove('abrir');
      await _tocar(tester, 'preparacion_db_reintentar');

      expect(_principal, findsOneWidget);
      expect(_db.envoltorio!.password, _password);
    });
  });

  group('Recuperación guiada (ADR-006)', () {
    testWidgets('dado que el almacén perdió la DEK y hay envoltorio, pide la contraseña y con la '
        'correcta abre la DB que ya estaba', (tester) async {
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: true);
      await _entrar(tester);

      expect(
        find.text('Tu almacenamiento seguro falló. Ingresá tu contraseña para recuperar tus datos'),
        findsOneWidget,
      );

      await tester.enterText(_boton('preparacion_db_password'), 'otra');
      await _tocar(tester, 'preparacion_db_recuperar');
      expect(find.text(const FailurePasswordNoAbreDatos().mensaje), findsOneWidget);
      expect(_principal, findsNothing);

      await tester.enterText(_boton('preparacion_db_password'), _password);
      await _tocar(tester, 'preparacion_db_recuperar');

      expect(_principal, findsOneWidget);
      expect(_db.archivo, isTrue, reason: 'nunca se borra');
    });

    testWidgets(
      'sin envoltorio, primero solo ofrece reintentar; "empezar de nuevo" aparece después '
      'de un reintento que vuelve a fallar',
      (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);

        expect(find.text(const FailureAlmacenSeguroSinRecuperacion().mensaje), findsOneWidget);
        expect(_boton('preparacion_db_reintentar'), findsOneWidget);
        expect(_boton('preparacion_db_empezar_de_nuevo'), findsNothing);

        await _tocar(tester, 'preparacion_db_reintentar');

        expect(_boton('preparacion_db_empezar_de_nuevo'), findsOneWidget);
        expect(_db.archivo, isTrue, reason: 'reintentar no borra nada');
      },
    );

    testWidgets(
      '"empezar de nuevo" pide confirmación: cancelar no borra; confirmar borra y prepara '
      'una DB nueva',
      (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_reintentar');

        await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
        expect(find.text(TextosPreparacionDbLocal.empezarDeNuevoDetalle), findsOneWidget);
        await _tocar(tester, 'preparacion_db_cancelar_empezar');
        expect(_db.llamadas, isNot(contains('descartar')));
        expect(_db.archivo, isTrue);

        await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
        await _tocar(tester, 'preparacion_db_confirmar_empezar');

        expect(_principal, findsOneWidget);
        expect(_db.llamadas, contains('descartar'));
        expect(
          _db.envoltorio!.password,
          _password,
          reason: 'la DB nueva ya tiene con qué recuperar',
        );
      },
    );
  });

  group('Cerrar sesión', () {
    testWidgets('desde una falla, vuelve al login sin tocar la DB', (tester) async {
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_cerrar_sesion');

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
      expect(_db.archivo, isTrue);
    });
  });

  group('Vista 13 (#222) — un estado por artboard', () {
    const pasos = [
      'Revisando el bloqueo de pantalla',
      'Creando y guardando tu clave',
      'Creando tu base cifrada',
    ];
    const apoyos = [
      'Lo que cargues queda cifrado en este teléfono. Se hace una sola vez.',
      'La clave se guarda en el almacenamiento seguro del teléfono. Nadie más la ve.',
      'Ya casi. Después vas a poder trabajar sin conexión.',
    ];

    for (final (n, paso) in [
      (1, PasoInicializacionDb.generandoClave),
      (2, PasoInicializacionDb.protegiendoClave),
      (3, PasoInicializacionDb.abriendoDb),
    ]) {
      testWidgets('A0$n en curso $n/3: contador, barra por pasos, lista de pasos y apoyo', (
        tester,
      ) async {
        await _montarEstado(tester, PreparandoDbLocal(paso: paso));

        expect(find.text('PRIMER INGRESO EN ESTE TELÉFONO'), findsOneWidget);
        expect(find.text('Preparando tu espacio seguro… $n/3'), findsOneWidget);
        for (final texto in pasos) {
          expect(find.text(texto), findsOneWidget);
        }
        expect(find.text(apoyos[n - 1]), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          final segmento = tester.widget<Container>(find.byKey(Key('preparacion_db_segmento_$i')));
          final lleno = (segmento.decoration! as BoxDecoration).color;
          final primario = Theme.of(tester.element(_preparacion)).colorScheme.primary;
          expect(lleno == primario, i < n, reason: 'segmento $i con $n/3');
        }
        // Los pasos anteriores, hechos; el actual, con el spinner; el resto, pendientes.
        expect(find.byIcon(Icons.check_circle), findsNWidgets(n - 1));
        expect(
          find.descendant(
            of: find.byKey(const Key('preparacion_db_pasos')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('verificando el equipo (sin número): el primer paso en curso y la barra vacía', (
      tester,
    ) async {
      await _montarEstado(tester, const PreparandoDbLocal());

      expect(find.text('Preparando tu espacio seguro…'), findsOneWidget);
      expect(find.text(apoyos[0]), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('A04 sin bloqueo de pantalla: título, texto de la HU, cómo configurarlo y «Ya lo '
        'configuré»', (tester) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);

      expect(find.text('PASO 1 DE 3 · EN PAUSA'), findsOneWidget);
      expect(find.text('Activá el bloqueo de pantalla'), findsOneWidget);
      expect(find.text(const FailureSinBloqueoPantalla().mensaje), findsOneWidget);
      expect(find.text('CÓMO CONFIGURARLO'), findsOneWidget);
      expect(find.text('Ajustes > Seguridad > Bloqueo de pantalla'), findsOneWidget);
      expect(find.text('Elegí PIN, patrón o contraseña y volvé a la app.'), findsOneWidget);
      expect(find.text('Ya lo configuré'), findsOneWidget);
      expect(
        _boton('preparacion_db_cerrar_sesion'),
        findsOneWidget,
        reason: 'nadie queda encerrado',
      );
    });

    testWidgets('A05 almacenamiento por software: «Continuar» deshabilitado hasta marcar el '
        'consentimiento; «Salir sin preparar» aborta', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);

      expect(find.text('PASO 2 DE 3 · EN PAUSA'), findsOneWidget);
      expect(find.text('Antes de seguir'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isFalse);
      expect(
        tester.widget<CheckboxListTile>(_boton('preparacion_db_entiendo_riesgo')).value,
        isFalse,
      );

      // Marcar y desmarcar vuelve a deshabilitar.
      await _tocar(tester, 'preparacion_db_entiendo_riesgo');
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isTrue);
      await _tocar(tester, 'preparacion_db_entiendo_riesgo');
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isFalse);

      await _tocar(tester, 'preparacion_db_cancelar_riesgo');
      expect(find.text('Salir sin preparar'), findsNothing);
      expect(find.text(TextosPreparacionDbLocal.otroCelular), findsOneWidget);
      expect(_db.consentimiento, isFalse);
    });

    testWidgets('A06 falla del almacenamiento: «No se pudo terminar», el texto de la HU, que no '
        'se perdió nada y «Reintentar desde cero»', (tester) async {
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();
      await _entrar(tester);

      expect(find.text('No se pudo terminar'), findsOneWidget);
      expect(find.text(const FailureAlmacenSeguro().mensaje), findsOneWidget);
      expect(
        find.text('Si reintentás, empezamos de cero. No se perdió nada: todavía no había datos.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar desde cero'), findsOneWidget);
      expect(
        _boton('preparacion_db_cerrar_sesion'),
        findsOneWidget,
        reason: 'nadie queda encerrado',
      );
    });

    testWidgets('A07 sin espacio: el texto de la HU como título, qué hacer y «Reintentar»', (
      tester,
    ) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      expect(find.text('No hay espacio suficiente para preparar el app'), findsOneWidget);
      expect(
        find.text(
          'Liberá espacio borrando fotos, videos o apps que no uses, y volvé a intentarlo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('A08 esquema posterior: bloqueante, con «Actualizar» y sin salida a borrar', (
      tester,
    ) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
      _db.fallas['abrir'] = const FailureEsquemaPosterior();
      await _entrar(tester);

      expect(find.text('ACTUALIZACIÓN NECESARIA'), findsOneWidget);
      expect(find.text('Actualizá la app'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(_boton('preparacion_db_empezar_de_nuevo'), findsNothing);
    });
  });

  group('Acciones y casos límite (#222)', () {
    Finder aviso() => _boton('preparacion_db_aviso_ajustes');

    testWidgets('con texto al 200 % el título y el aviso bajan de tamaño para no partir palabras '
        'como «Preparando» o «almacenamiento»', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      double? tamanio(Finder f) => tester.widget<Text>(f).style?.fontSize;

      // Texto 1.0: el tamaño del tema.
      await _montarEstado(
        tester,
        const PreparandoDbLocal(paso: PasoInicializacionDb.protegiendoClave),
      );
      final titulo = find.byKey(const Key('preparacion_db_progreso'));
      final base = Theme.of(tester.element(titulo)).textTheme.headlineMedium!.fontSize!;
      expect(tamanio(titulo), base);

      // Texto 2.0: más chico que el del tema.
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const SizedBox());
      await _montarEstado(
        tester,
        const PreparandoDbLocal(paso: PasoInicializacionDb.protegiendoClave),
      );
      expect(tamanio(titulo), lessThan(base));

      // El aviso de A05, igual.
      _db.nivel = NivelAlmacenSeguro.software;
      await tester.pumpWidget(const SizedBox());
      await _entrar(tester);
      final aviso = find.byKey(const Key('preparacion_db_mensaje'));
      final baseAviso = Theme.of(tester.element(aviso)).textTheme.bodyLarge!.fontSize!;
      expect(tamanio(aviso), lessThan(baseAviso));
    });

    testWidgets('A04 «Abrir Ajustes» abre los ajustes de seguridad y no cambia la pantalla', (
      tester,
    ) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_abrir_ajustes');

      expect(_ajustes.llamadas, ['seguridad']);
      expect(aviso(), findsNothing);
      expect(find.text('Activá el bloqueo de pantalla'), findsOneWidget);
    });

    testWidgets('A04 si no se pueden abrir los ajustes, lo dice y deja reintentar', (tester) async {
      _db.bloqueoPantalla = false;
      _ajustes.resultado = false;
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_abrir_ajustes');

      expect(find.text(TextosPreparacionDbLocal.noPudimosAbrirAjustes), findsOneWidget);
      expect(_botonHabilitado(tester, 'preparacion_db_abrir_ajustes'), isTrue);

      _ajustes.resultado = true;
      await _tocar(tester, 'preparacion_db_abrir_ajustes');
      expect(_ajustes.llamadas, ['seguridad', 'seguridad']);
      expect(aviso(), findsNothing);
    });

    testWidgets(
      'A04 si el abridor lanza una excepción, no queda trabado: avisa y deja reintentar',
      (tester) async {
        _db.bloqueoPantalla = false;
        _ajustes.lanza = true;
        await _entrar(tester);

        await _tocar(tester, 'preparacion_db_abrir_ajustes');

        expect(find.text(TextosPreparacionDbLocal.noPudimosAbrirAjustes), findsOneWidget);
        expect(_botonHabilitado(tester, 'preparacion_db_abrir_ajustes'), isTrue);

        _ajustes.lanza = false;
        await _tocar(tester, 'preparacion_db_abrir_ajustes');
        expect(aviso(), findsNothing);
        expect(_ajustes.llamadas, ['seguridad', 'seguridad']);
      },
    );

    testWidgets('A07 si el abridor lanza una excepción, no queda trabado', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      _ajustes.lanza = true;
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_abrir_almacenamiento');

      expect(find.text(TextosPreparacionDbLocal.noPudimosAbrirAjustes), findsOneWidget);
      expect(_botonHabilitado(tester, 'preparacion_db_abrir_almacenamiento'), isTrue);
    });

    testWidgets('A04 doble toque en «Abrir Ajustes»: una sola apertura', (tester) async {
      _db.bloqueoPantalla = false;
      _ajustes.espera = Completer<void>();
      await _entrar(tester);

      await tester.tap(_boton('preparacion_db_abrir_ajustes'));
      await tester.pump();
      expect(_botonHabilitado(tester, 'preparacion_db_abrir_ajustes'), isFalse);
      await tester.tap(_boton('preparacion_db_abrir_ajustes'), warnIfMissed: false);
      await tester.pump();
      expect(_ajustes.llamadas, ['seguridad']);

      _ajustes.espera!.complete();
      await tester.pumpAndSettle();
      expect(_botonHabilitado(tester, 'preparacion_db_abrir_ajustes'), isTrue);
    });

    testWidgets('A04 «Ya lo configuré» con el bloqueo puesto termina la preparación; doble toque '
        'no prepara dos veces', (tester) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);
      _db.bloqueoPantalla = true;

      await tester.tap(_boton('preparacion_db_reintentar'));
      await tester.tap(_boton('preparacion_db_reintentar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_db.llamadas.where((l) => l == 'crearDek'), hasLength(1));
    });

    testWidgets('A04 si el reintento vuelve a fallar, la pantalla sigue con los botones '
        'habilitados (nada queda trabado)', (tester) async {
      _db.bloqueoPantalla = false;
      await _entrar(tester);

      for (var i = 0; i < 2; i++) {
        await _tocar(tester, 'preparacion_db_reintentar');
        expect(find.text('Activá el bloqueo de pantalla'), findsOneWidget);
        expect(_boton('preparacion_db_reintentar'), findsOneWidget);
        expect(_botonHabilitado(tester, 'preparacion_db_abrir_ajustes'), isTrue);
      }
    });

    testWidgets('A05 salir y volver a la advertencia: el consentimiento no queda marcado', (
      tester,
    ) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);
      await _tocar(tester, 'preparacion_db_entiendo_riesgo');
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isTrue);

      await _tocar(tester, 'preparacion_db_cancelar_riesgo');
      await _tocar(tester, 'preparacion_db_continuar_con_este');

      expect(
        tester.widget<CheckboxListTile>(_boton('preparacion_db_entiendo_riesgo')).value,
        isFalse,
      );
      expect(_botonHabilitado(tester, 'preparacion_db_aceptar_riesgo'), isFalse);
    });

    testWidgets('A05 doble toque en «Continuar»: crea la DB una sola vez', (tester) async {
      _db.nivel = NivelAlmacenSeguro.software;
      await _entrar(tester);
      await _tocar(tester, 'preparacion_db_entiendo_riesgo');

      await tester.tap(_boton('preparacion_db_aceptar_riesgo'));
      await tester.tap(_boton('preparacion_db_aceptar_riesgo'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_db.llamadas.where((l) => l == 'crearDek'), hasLength(1));
    });

    testWidgets('A06 «Reintentar desde cero» que vuelve a fallar deja reintentar otra vez', (
      tester,
    ) async {
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_reintentar');
      expect(find.text('No se pudo terminar'), findsOneWidget);
      expect(_botonHabilitado(tester, 'preparacion_db_reintentar'), isTrue);

      _db.fallas.remove('crearDek');
      await _tocar(tester, 'preparacion_db_reintentar');
      expect(_principal, findsOneWidget);
    });

    testWidgets('A07 «Abrir almacenamiento» abre los ajustes de almacenamiento; si falla, lo '
        'dice', (tester) async {
      _db.fallas['abrir'] = const FailureSinEspacio();
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_abrir_almacenamiento');
      expect(_ajustes.llamadas, ['almacenamiento']);
      expect(aviso(), findsNothing);

      _ajustes.resultado = false;
      await _tocar(tester, 'preparacion_db_abrir_almacenamiento');
      expect(find.text(TextosPreparacionDbLocal.noPudimosAbrirAjustes), findsOneWidget);
      expect(_boton('preparacion_db_reintentar'), findsOneWidget);
    });

    testWidgets('A08 «Actualizar» tocado dos veces muestra el cómo una sola vez', (tester) async {
      _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
      _db.fallas['abrir'] = const FailureEsquemaPosterior();
      await _entrar(tester);

      await _tocar(tester, 'preparacion_db_actualizar');
      await _tocar(tester, 'preparacion_db_actualizar');

      expect(find.text(TextosPreparacionDbLocal.actualizarComo), findsOneWidget);
    });

    testWidgets('el campo de contraseña acepta un texto muy largo sin overflow al 200 %', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _entrar(tester, restaurada: true);

      await tester.enterText(_boton('preparacion_db_password'), 'a' * 400);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Accesibilidad', () {
    // Cada estado de la pantalla, preparado sobre el fake.
    final estados = <String, Future<void> Function(WidgetTester)>{
      'progreso 2/3': (tester) async {
        _db.argon2idPendiente = Completer<void>();
        await _entrar(tester, esperar: false);
        await tester.pump();
        await tester.pump();
      },
      'progreso 1/3': (tester) =>
          _montarEstado(tester, const PreparandoDbLocal(paso: PasoInicializacionDb.generandoClave)),
      'progreso 3/3': (tester) =>
          _montarEstado(tester, const PreparandoDbLocal(paso: PasoInicializacionDb.abriendoDb)),
      'sin bloqueo': (tester) async {
        _db.bloqueoPantalla = false;
        await _entrar(tester);
      },
      'consentimiento marcado': (tester) async {
        _db.nivel = NivelAlmacenSeguro.software;
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_entiendo_riesgo');
      },
      'falla del almacenamiento': (tester) async {
        _db.fallas['crearDek'] = const FailureAlmacenSeguro();
        await _entrar(tester);
      },
      'consentimiento': (tester) async {
        _db.nivel = NivelAlmacenSeguro.software;
        await _entrar(tester);
      },
      'otro celular': (tester) async {
        _db.nivel = NivelAlmacenSeguro.software;
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_cancelar_riesgo');
      },
      'recuperación con error': (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: true);
        await _entrar(tester);
        await tester.enterText(_boton('preparacion_db_password'), 'otra');
        await _tocar(tester, 'preparacion_db_recuperar');
      },
      'sin recuperación, con empezar de nuevo': (tester) async {
        _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_reintentar');
      },
      'confirmar contraseña con error': (tester) async {
        await _entrar(tester, restaurada: true);
        await tester.enterText(_boton('preparacion_db_password'), 'equivocada');
        await _tocar(tester, 'preparacion_db_confirmar_password');
      },
      'sin bloqueo con aviso de ajustes': (tester) async {
        _db.bloqueoPantalla = false;
        _ajustes.resultado = false;
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_abrir_ajustes');
      },
      'sin espacio': (tester) async {
        _db.fallas['abrir'] = const FailureSinEspacio();
        await _entrar(tester);
      },
      'sin espacio con aviso de ajustes': (tester) async {
        _db.fallas['abrir'] = const FailureSinEspacio();
        _ajustes.resultado = false;
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_abrir_almacenamiento');
      },
      'esquema posterior': (tester) async {
        _dbExistente(dekEnAlmacen: true, conEnvoltorio: true);
        _db.fallas['abrir'] = const FailureEsquemaPosterior();
        await _entrar(tester);
        await _tocar(tester, 'preparacion_db_actualizar');
      },
    };

    for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
      testWidgets('$nombre: tamaño de toque, etiquetas y contraste en 390x844', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await preparar(tester);

        expect(_preparacion, findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        _db.argon2idPendiente?.complete();
        handle.dispose();
      });

      for (final (tam, escala) in [
        (const Size(360, 640), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 1.0),
        (const Size(412, 915), 2.0),
      ]) {
        testWidgets('$nombre: sin overflow en ${tam.width.toInt()}x${tam.height.toInt()} con texto '
            '$escala', (tester) async {
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await preparar(tester);

          expect(_preparacion, findsOneWidget);
          expect(tester.takeException(), isNull);
          _db.argon2idPendiente?.complete();
        });
      }

      testWidgets('$nombre: sin overflow con el texto al 200 % en 360x740', (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await preparar(tester);

        expect(_preparacion, findsOneWidget);
        expect(tester.takeException(), isNull);
        _db.argon2idPendiente?.complete();
      });
    }

    testWidgets('el diálogo de "empezar de nuevo": tamaño de toque, etiquetas y contraste', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _dbExistente(dekEnAlmacen: false, conEnvoltorio: false);
      await _entrar(tester);
      await _tocar(tester, 'preparacion_db_reintentar');
      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  test('los textos de la HU no cambian sin querer', () {
    expect(TextosPreparacionDbLocal.progreso(1), 'Preparando tu espacio seguro… 1/3');
    expect(TextosPreparacionDbLocal.aceptarRiesgo, 'Entiendo el riesgo y quiero continuar');
  });
}
