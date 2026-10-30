// HU-UBI-010 / vista 32C «Editar persona» (C·01 a C·04) y los casos límite de cada flujo: doble toque,
// falla a mitad del guardado, reintento con lo último escrito, volver atrás y reentrar, descartar,
// textos largos y texto al 200 %. No hay estado «sin conexión»: la edición es solo local.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_persona_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

const _guardar = 'Guardar cambios';
const _guardarIgual = 'Guardar igual';
const _bajaYNueva = 'Dar de baja y crear nueva';
const _nombre = 'Obligatorio';
const _apellido = 'Apellido';
const _telefono = '09X XXX XXX';
const _cambiosGuardados = 'Cambios guardados en tu teléfono.';
const _noPudimos = 'No pudimos guardar a la persona. Probá de nuevo.';

Finder _campo(String sugerencia) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == sugerencia);

TextField _textField(WidgetTester tester, String sugerencia) =>
    tester.widget<TextField>(_campo(sugerencia));

Future<void> _escribir(WidgetTester tester, String sugerencia, String texto) async {
  await tester.enterText(_campo(sugerencia), texto);
  await tester.pump();
}

Finder _boton(String etiqueta) => find.widgetWithText(FilledButton, etiqueta);

Future<void> _tocar(WidgetTester tester, String etiqueta) async {
  await tester.tap(_boton(etiqueta));
  await asentar(tester);
}

/// El canvas 32C·03: pasar de «María Fernández» a otra persona.
Future<void> _cambioTotal(WidgetTester tester) async {
  await _escribir(tester, _nombre, 'Roberto');
  await _escribir(tester, _apellido, 'Suárez');
  await _escribir(tester, _telefono, '091 222 333');
}

double _contraste(Color a, Color b) {
  final (mayor, menor) = a.computeLuminance() > b.computeLuminance() ? (a, b) : (b, a);
  return (mayor.computeLuminance() + 0.05) / (menor.computeLuminance() + 0.05);
}

void main() {
  group('C·01 · editar', () {
    testWidgets('dado «María Fernández», cuando se abre, muestra el candado, los tres campos '
        'cargados y «Guardar cambios», sin primera nota', (tester) async {
      await montarEdicion(tester);

      expect(find.text('EDITAR PERSONA'), findsOneWidget);
      expect(find.text('Editar persona'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 101'), findsOneWidget);
      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('NOMBRE'), findsOneWidget);
      expect(find.text('APELLIDO (OPCIONAL)'), findsOneWidget);
      expect(find.text('TELÉFONO (OPCIONAL)'), findsOneWidget);
      expect(find.text('PRIMERA NOTA (OPCIONAL)'), findsNothing);
      expect(find.text('María'), findsOneWidget);
      expect(find.text('Fernández'), findsOneWidget);
      expect(find.text('098 765 432'), findsOneWidget);
      expect(_boton(_guardar), findsOneWidget);
      expect(_boton('Reintentar'), findsNothing);
      expect(find.text('Cargando a la persona'), findsNothing);
    });

    testWidgets('dado el apellido "Gonzalez", cuando se corrige a "González" y se guarda, el '
        'cambio se aplica y vuelve la persona editada', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(apellido: 'Gonzalez');
      final resultado = await montarEdicion(tester, repo: repo);

      await _escribir(tester, _apellido, 'González');
      await _tocar(tester, _guardar);

      final edicion = repo.editadas.single;
      expect(edicion.personaId, 'per-1');
      expect(edicion.nombre, 'María');
      expect(edicion.apellido, 'González');
      expect(edicion.telefono, '098 765 432');
      expect(edicion.ahora, relojDeEdicion);
      final r = resultado.resultado;
      expect(r, isA<PersonaEditada>());
      expect((r! as PersonaEditada).persona.apellido, 'González');
      expect(resultado.cierres, 1);
      expect(find.text('Editar persona'), findsNothing);
    });

    testWidgets('dado un teléfono nuevo, cuando se guarda, el repositorio recibe los textos sin '
        'espacios de más', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, '  María   José ');
      await _escribir(tester, _telefono, ' 099  000 111 ');
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.nombre, 'María José');
      expect(repo.editadas.single.telefono, '099 000 111');
    });

    testWidgets('dado el apellido y el teléfono vaciados, cuando se guarda, quedan sin dato '
        '(ambos son opcionales)', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _apellido, '');
      await _escribir(tester, _telefono, '');
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.apellido, '');
      expect(repo.editadas.single.telefono, isNull);
    });

    testWidgets('dado una persona sin apellido ni teléfono, cuando se abre y se guarda sin tocar '
        'nada, no escribe', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(apellido: '', telefono: null);
      final resultado = await montarEdicion(tester, repo: repo);

      expect(find.text('Jorge'), findsNothing);
      await _tocar(tester, _guardar);

      expect(repo.editadas, isEmpty);
      expect(resultado.cierres, 1);
    });

    testWidgets('dado que no se cambió nada, cuando se toca «Guardar cambios», cierra sin escribir '
        'ni avisar', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarEdicion(tester, repo: repo);

      await _tocar(tester, _guardar);

      expect(repo.editadas, isEmpty);
      expect(resultado.resultado, isNull);
      expect(resultado.cierres, 1);
      expect(find.text(_cambiosGuardados), findsNothing);
      expect(find.text('Editar persona'), findsNothing);
    });

    testWidgets('dado un cambio solo de espacios en blanco, cuando se guarda, tampoco escribe', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, '  María ');
      await _tocar(tester, _guardar);

      expect(repo.editadas, isEmpty);
    });
  });

  group('C·04 · guardado', () {
    testWidgets('dado un cambio guardado, cuando se vuelve a la pantalla de arranque, avisa '
        '«Cambios guardados en tu teléfono.»', (tester) async {
      await montarEdicion(tester);

      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);

      expect(find.text(_cambiosGuardados), findsOneWidget);
      expect(find.text('abrir edición'), findsOneWidget);
    });

    testWidgets('dado un aviso viejo en la pantalla de arranque, cuando se abre la edición, el '
        'aviso se va (no tapa el botón de abajo)', (tester) async {
      await montarEdicion(tester);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);
      expect(find.text(_cambiosGuardados), findsOneWidget);

      await tester.tap(find.text('abrir edición'));
      await asentar(tester);

      expect(find.text(_cambiosGuardados), findsNothing);
    });
  });

  group('C·02 · nombre vacío', () {
    testWidgets('dado el nombre vaciado, cuando se escribe, dice al instante «El nombre no puede '
        'quedar vacío.» y el botón se ve apagado', (tester) async {
      await montarEdicion(tester);

      await _escribir(tester, _nombre, '');

      expect(find.text('El nombre no puede quedar vacío.'), findsOneWidget);
      expect(find.text('Escribí al menos el nombre.'), findsNothing);
    });

    testWidgets(
      'dado el nombre vacío, cuando toca «Guardar cambios», no guarda, deja el foco en el '
      'nombre y lo anuncia',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        await montarEdicion(tester, repo: repo);
        await _escribir(tester, _nombre, '   ');
        tester.takeAnnouncements();

        await _tocar(tester, _guardar);

        expect(repo.editadas, isEmpty);
        expect(_textField(tester, _nombre).focusNode?.hasFocus, isTrue);
        expect(find.text('Editar persona'), findsOneWidget);
        expect(
          tester.takeAnnouncements().map((a) => a.message),
          contains('El nombre no puede quedar vacío.'),
        );
      },
    );

    testWidgets(
      'dado el botón apagado a la vista, cuando se mide, el texto cumple el contraste AA y '
      'sigue siendo tocable',
      (tester) async {
        await montarEdicion(tester);
        await _escribir(tester, _nombre, '');

        final boton = tester.widget<FilledButton>(_boton(_guardar));
        final fondo = boton.style!.backgroundColor!.resolve({})!;
        final texto = boton.style!.foregroundColor!.resolve({})!;
        expect(_contraste(fondo, texto), greaterThanOrEqualTo(4.5));
        expect(boton.onPressed, isNotNull);
      },
    );

    testWidgets('dado el nombre vacío, cuando se escribe uno de nuevo, el error se va y se puede '
        'guardar', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _nombre, '');

      await _escribir(tester, _nombre, 'Marta');
      expect(find.text('El nombre no puede quedar vacío.'), findsNothing);
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.nombre, 'Marta');
    });

    testWidgets('dado un nombre de una letra, cuando se escribe, no regaña a mitad de tipeo; al '
        'tocar guardar dice que necesita 2 letras', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, 'M');
      expect(find.text('El nombre necesita al menos 2 letras.'), findsNothing);
      await _tocar(tester, _guardar);

      expect(find.text('El nombre necesita al menos 2 letras.'), findsOneWidget);
      expect(repo.editadas, isEmpty);
    });

    testWidgets('dado el nombre vaciado y dejado, cuando el foco pasa a otro campo, el error sigue '
        'a la vista', (tester) async {
      await montarEdicion(tester);

      await tester.tap(_campo(_nombre));
      await tester.pump();
      await _escribir(tester, _nombre, '');
      await tester.tap(_campo(_apellido));
      await tester.pump();

      expect(find.text('El nombre no puede quedar vacío.'), findsOneWidget);
    });
  });

  group('teléfono inválido (mismas validaciones del alta)', () {
    testWidgets('dado «099 12», cuando toca guardar, dice que le faltan números, no guarda y deja '
        'el foco en el teléfono', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _telefono, '099 12');
      await _tocar(tester, _guardar);

      expect(find.text('Revisá el teléfono: le faltan números.'), findsOneWidget);
      expect(repo.editadas, isEmpty);
      expect(_textField(tester, _telefono).focusNode?.hasFocus, isTrue);
    });

    testWidgets('dado el error del teléfono, cuando se completa el número, el error se va y se '
        'guarda', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 12');
      await _tocar(tester, _guardar);

      await _escribir(tester, _telefono, '099 123 456');
      expect(find.text('Revisá el teléfono: le faltan números.'), findsNothing);
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.telefono, '099 123 456');
    });

    testWidgets('dado un nombre vacío y un teléfono inválido, cuando toca guardar, el foco va al '
        'nombre (el primero del formulario)', (tester) async {
      await montarEdicion(tester);
      await _escribir(tester, _nombre, '');
      await _escribir(tester, _telefono, 'abc');

      await _tocar(tester, _guardar);

      expect(_textField(tester, _nombre).focusNode?.hasFocus, isTrue);
      expect(find.textContaining('solo puede tener números'), findsOneWidget);
    });

    testWidgets('dado un número del exterior, cuando guarda, no se bloquea', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _telefono, '+54 9 11 5555 1234');
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.telefono, '+54 9 11 5555 1234');
    });
  });

  group('C·03 · ¿es otra persona?', () {
    const aviso =
        'Cambiaste nombre, apellido y teléfono. Si es otra persona, conviene dar de baja a María '
        'y registrar a Roberto aparte, para no mezclar el historial.';

    testWidgets('dado un cambio que parece otra persona, cuando se escribe, muestra el aviso del '
        'canvas, «Dar de baja y crear nueva» y el botón pasa a «Guardar igual»', (tester) async {
      await montarEdicion(tester, criterio: CriterioOtraPersonaFijo());

      await _cambioTotal(tester);

      expect(find.text(aviso), findsOneWidget);
      expect(find.text(_bajaYNueva), findsOneWidget);
      expect(_boton(_guardarIgual), findsOneWidget);
      expect(_boton(_guardar), findsNothing);
    });

    testWidgets('dado el aviso, cuando se toca «Guardar igual», guarda el cambio tal cual', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarEdicion(
        tester,
        repo: repo,
        criterio: CriterioOtraPersonaFijo(),
      );
      await _cambioTotal(tester);

      await _tocar(tester, _guardarIgual);

      final edicion = repo.editadas.single;
      expect(edicion.nombre, 'Roberto');
      expect(edicion.apellido, 'Suárez');
      expect(edicion.telefono, '091 222 333');
      expect(resultado.resultado, isA<PersonaEditada>());
      expect(find.text(_cambiosGuardados), findsOneWidget);
    });

    testWidgets('dado el aviso, cuando se toca «Dar de baja y crear nueva», vuelve con lo escrito '
        'para que el llamador dé de baja y abra el alta, y no escribe nada', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarEdicion(
        tester,
        repo: repo,
        criterio: CriterioOtraPersonaFijo(),
      );
      await _cambioTotal(tester);

      await tester.ensureVisible(find.text(_bajaYNueva));
      await tester.tap(find.text(_bajaYNueva));
      await asentar(tester);

      expect(repo.editadas, isEmpty);
      final r = resultado.resultado;
      expect(r, isA<DarDeBajaYCrearNuevaElegido>());
      final elegido = r! as DarDeBajaYCrearNuevaElegido;
      expect(elegido.original.id, 'per-1');
      expect(elegido.original.nombre, 'María');
      expect(elegido.nombre, 'Roberto');
      expect(elegido.apellido, 'Suárez');
      expect(elegido.telefono, '091 222 333');
      expect(find.text('Editar persona'), findsNothing);
      expect(find.text(_cambiosGuardados), findsNothing);
    });

    testWidgets('dado un doble toque en «Dar de baja y crear nueva», cuando termina, la pantalla '
        'de abajo sigue ahí (se cerró una sola vez)', (tester) async {
      final resultado = await montarEdicion(tester, criterio: CriterioOtraPersonaFijo());
      await _cambioTotal(tester);

      final enlace = find.text(_bajaYNueva);
      await tester.ensureVisible(enlace);
      await tester.tap(enlace);
      await tester.tap(enlace, warnIfMissed: false);
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(find.text('abrir edición'), findsOneWidget);
    });

    testWidgets('dado que la regla todavía no está decidida (criterio por defecto), cuando se '
        'cambia todo, no sale el aviso y el botón sigue en «Guardar cambios»', (tester) async {
      await montarEdicion(tester);

      await _cambioTotal(tester);

      expect(find.textContaining('Si es otra persona'), findsNothing);
      expect(find.text(_bajaYNueva), findsNothing);
      expect(_boton(_guardar), findsOneWidget);
      expect(_boton(_guardarIgual), findsNothing);
    });

    testWidgets('dado el aviso a la vista, cuando se deja de parecer otra persona, el aviso se va '
        'y el botón vuelve a «Guardar cambios»', (tester) async {
      final criterio = CriterioOtraPersonaFijo();
      await montarEdicion(tester, criterio: criterio);
      await _cambioTotal(tester);
      expect(_boton(_guardarIgual), findsOneWidget);

      criterio.respuesta = false;
      await _escribir(tester, _apellido, 'Suárez Pérez');

      expect(find.text(_bajaYNueva), findsNothing);
      expect(_boton(_guardar), findsOneWidget);
    });

    testWidgets('dado un cambio y luego volver a lo original, cuando se escribe, no hay aviso (no '
        'hay cambio que juzgar)', (tester) async {
      final criterio = CriterioOtraPersonaFijo();
      await montarEdicion(tester, criterio: criterio);
      await _cambioTotal(tester);

      await _escribir(tester, _nombre, 'María');
      await _escribir(tester, _apellido, 'Fernández');
      await _escribir(tester, _telefono, '098 765 432');

      expect(find.text(_bajaYNueva), findsNothing);
      expect(_boton(_guardar), findsOneWidget);
    });

    testWidgets('dado un formulario que no sirve, cuando se escribe, no se consulta el criterio ni '
        'sale el aviso', (tester) async {
      final criterio = CriterioOtraPersonaFijo();
      await montarEdicion(tester, criterio: criterio);

      await _escribir(tester, _nombre, '');

      expect(criterio.consultas, 0);
      expect(find.text(_bajaYNueva), findsNothing);
    });

    testWidgets('dado que cambiaron solo el nombre y el apellido, cuando sale el aviso, nombra '
        'solo esos dos campos', (tester) async {
      await montarEdicion(tester, criterio: CriterioOtraPersonaFijo());

      await _escribir(tester, _nombre, 'Roberto');
      await _escribir(tester, _apellido, 'Suárez');

      expect(
        find.text(
          'Cambiaste nombre y apellido. Si es otra persona, conviene dar de baja a María y '
          'registrar a Roberto aparte, para no mezclar el historial.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dado el aviso y el texto al 200 % en un teléfono chico, cuando se muestra, no se '
        'desborda y los dos botones se alcanzan', (tester) async {
      await montarEdicion(
        tester,
        criterio: CriterioOtraPersonaFijo(),
        escala: 2,
        tamano: const Size(320, 568),
      );

      await _cambioTotal(tester);
      await tester.ensureVisible(find.text(_bajaYNueva));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(_bajaYNueva), findsOneWidget);
      expect(_boton(_guardarIgual), findsOneWidget);
    });
  });

  group('cargar a la persona', () {
    testWidgets('dado que la lectura tarda, cuando se abre, muestra «Cargando a la persona» sin '
        'formulario; al llegar, el formulario', (tester) async {
      final repo = PersonaRepositorioFalso()..compuertaLeer = Completer<void>();
      await montarEdicion(tester, repo: repo);

      expect(find.text('Cargando a la persona'), findsNothing); // es solo para el lector
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Editar persona'), findsOneWidget);

      repo.compuertaLeer!.complete();
      await asentar(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TextField), findsNWidgets(3));
    });

    testWidgets('dado que la lectura tarda, cuando se lee con el lector de pantalla, dice que '
        'está cargando', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = PersonaRepositorioFalso()..compuertaLeer = Completer<void>();
      await montarEdicion(tester, repo: repo);

      expect(find.bySemanticsLabel('Cargando a la persona'), findsOneWidget);

      repo.compuertaLeer!.complete();
      await asentar(tester);
      handle.dispose();
    });

    testWidgets('dado que la lectura falla, cuando se abre, avisa y «Reintentar» vuelve a leer y '
        'muestra el formulario', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..fallaAlLeerParaEditar = const FailureInesperado(causa: 'x');
      await montarEdicion(tester, repo: repo);

      expect(find.text('No pudimos leer los datos de la persona en tu teléfono.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await asentar(tester);

      expect(repo.lecturasParaEditar, 2);
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('No pudimos leer los datos de la persona en tu teléfono.'), findsNothing);
    });

    testWidgets('dado que la persona ya no está en el teléfono, cuando se abre, lo dice y «Volver» '
        'cierra', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarEdicion(
        tester,
        repo: repo..contextos['per-1'] = contextoDeEdicion(),
      );
      repo.contextos.clear();
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      await tester.tap(find.text('abrir edición'));
      await asentar(tester);

      expect(find.text('La persona ya no está en tu teléfono. Volvé atrás.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Volver'));
      await asentar(tester);

      expect(resultado.cierres, 2);
      expect(resultado.resultado, isNull);
    });
  });

  group('solo lectura (32B·04 y 32B·08)', () {
    testWidgets('dado una persona dada de baja, cuando se abre, dice desde cuándo y que no se '
        'edita, sin formulario', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(
          causa: CausaSoloLectura.personaDeBaja,
          bajaDesde: DateTime.utc(2026, 10, 22, 15),
        );
      await montarEdicion(tester, repo: repo);

      expect(
        find.text('María está de baja desde el 22/10. Sus datos no se pueden editar.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(_boton(_guardar), findsNothing);
      expect(find.text('Editar persona'), findsOneWidget);
    });

    testWidgets('dado un depto dado de baja, cuando se abre, dice cuál y dónde', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(
          causa: CausaSoloLectura.espacioDeBaja,
          numeroDepto: '3B',
          direccion: 'Mataojo 2044',
        );
      await montarEdicion(tester, repo: repo);

      expect(
        find.text('El depto 3B de Mataojo 2044 está dado de baja. Sus datos no se pueden editar.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('dado una persona sin ningún depto activo, cuando se abre, lo dice', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(causa: CausaSoloLectura.sinEspacioActivo);
      await montarEdicion(tester, repo: repo);

      expect(
        find.text('María ya no está en ningún depto activo. Sus datos no se pueden editar.'),
        findsOneWidget,
      );
    });

    testWidgets('dado el aviso de solo lectura, cuando se toca «Volver», cierra sin resultado', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(causa: CausaSoloLectura.sinEspacioActivo);
      final resultado = await montarEdicion(tester, repo: repo);

      await tester.tap(find.text('Volver'));
      await asentar(tester);

      expect(resultado.cierres, 1);
      expect(resultado.resultado, isNull);
      expect(repo.editadas, isEmpty);
    });

    testWidgets('dado que la persona se dio de baja mientras estaba abierta la edición, cuando '
        'guarda, el aviso dice por qué y lo escrito sigue ahí', (tester) async {
      final repo = PersonaRepositorioFalso(); // el `resultadosModificar` va aparte
      repo.resultadosModificar.add(
        FailureValidacion(campos: {'persona': MotivoRechazoPersona.personaSoloLectura.mensaje}),
      );
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');

      await _tocar(tester, _guardar);

      expect(find.text(MotivoRechazoPersona.personaSoloLectura.mensaje), findsOneWidget);
      expect(find.text('099 000 111'), findsOneWidget);
      expect(_boton('Reintentar'), findsOneWidget);
    });
  });

  group('error al guardar', () {
    testWidgets(
      'dado que guardar falla, cuando termina, muestra el aviso, conserva lo escrito y el '
      'botón pasa a «Reintentar», habilitado',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
        await montarEdicion(tester, repo: repo);
        await _escribir(tester, _telefono, '099 000 111');

        await _tocar(tester, _guardar);

        expect(find.text(_noPudimos), findsOneWidget);
        expect(_boton('Reintentar'), findsOneWidget);
        expect(_boton(_guardar), findsNothing);
        expect(tester.widget<FilledButton>(_boton('Reintentar')).onPressed, isNotNull);
        expect(find.text('099 000 111'), findsOneWidget);
        expect(find.text('Guardando…'), findsNothing);
        expect(_textField(tester, _telefono).readOnly, isFalse);
      },
    );

    testWidgets(
      'dado que guardar falló, cuando se corrige lo escrito y se reintenta, sale bien con '
      'lo último escrito y vuelve la persona',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
        final resultado = await montarEdicion(tester, repo: repo);
        await _escribir(tester, _telefono, '099 000 111');
        await _tocar(tester, _guardar);

        await _escribir(tester, _telefono, '099 222 333');
        await _tocar(tester, 'Reintentar');

        expect(repo.editadas, hasLength(2));
        expect(repo.editadas[0].telefono, '099 000 111');
        expect(repo.editadas[1].telefono, '099 222 333');
        expect(resultado.resultado, isA<PersonaEditada>());
        expect(resultado.cierres, 1);
        expect(find.text(_cambiosGuardados), findsOneWidget);
      },
    );

    testWidgets(
      'dado que falla dos veces seguidas, cuando reintenta, el botón vuelve a habilitarse '
      'cada vez y nunca queda «Guardando…»',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..resultadosModificar.addAll([
            const FailureInesperado(causa: 'x'),
            const FailureInesperado(causa: 'y'),
          ]);
        await montarEdicion(tester, repo: repo);
        await _escribir(tester, _telefono, '099 000 111');
        await _tocar(tester, _guardar);

        await _tocar(tester, 'Reintentar');

        expect(find.text(_noPudimos), findsOneWidget);
        expect(tester.widget<FilledButton>(_boton('Reintentar')).onPressed, isNotNull);
        expect(find.text('Guardando…'), findsNothing);
        expect(find.text('Editar persona'), findsOneWidget);
      },
    );

    testWidgets('dado que el repositorio lanza una excepción con datos, cuando guarda, la pantalla '
        'muestra el aviso y no el detalle', (tester) async {
      final repo = _RepoQueLanza();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');

      await _tocar(tester, _guardar);

      expect(find.text(_noPudimos), findsOneWidget);
      expect(find.textContaining('INSERT'), findsNothing);
      expect(find.textContaining('Fernández…'), findsNothing);
      expect(_boton('Reintentar'), findsOneWidget);
    });

    testWidgets('dado el aviso de falla y el texto al 200 % en un teléfono chico, cuando se '
        'muestra, no se desborda', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..resultadosModificar.add(const FailureInesperado(causa: 'x'));
      await montarEdicion(tester, repo: repo, escala: 2, tamano: const Size(320, 568));
      await _escribir(tester, _telefono, '099 000 111');

      await _tocar(tester, _guardar);

      expect(tester.takeException(), isNull);
      expect(find.text(_noPudimos), findsOneWidget);
      expect(_boton('Reintentar'), findsOneWidget);
    });
  });

  group('casos límite del guardado', () {
    testWidgets('dado un doble toque en «Guardar cambios», cuando el guardado está en curso, solo '
        'se guarda una vez', (tester) async {
      final repo = PersonaRepositorioFalso()..compuertaModificar = Completer<void>();
      final resultado = await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');

      // Dos toques sin fotograma en el medio: el segundo llega antes de que el botón se apague.
      final boton = _boton(_guardar);
      await tester.tap(boton);
      await tester.tap(boton);
      await tester.pump();

      expect(find.text('Guardando…'), findsOneWidget);
      expect(repo.editadas, hasLength(1));

      repo.compuertaModificar!.complete();
      await asentar(tester);

      expect(repo.editadas, hasLength(1));
      expect(resultado.cierres, 1);
      expect(find.text('abrir edición'), findsOneWidget);
    });

    testWidgets(
      'dado un doble toque sin nada que guardar, cuando cierra, se cierra una sola vez (no '
      'arrastra la pantalla de abajo)',
      (tester) async {
        final resultado = await montarEdicion(tester);

        final boton = _boton(_guardar);
        await tester.tap(boton);
        await tester.tap(boton, warnIfMissed: false);
        await asentar(tester);

        expect(resultado.cierres, 1);
        expect(find.text('abrir edición'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se intenta salir con «Cerrar» o con atrás, no se '
      'sale',
      (tester) async {
        final repo = PersonaRepositorioFalso()..compuertaModificar = Completer<void>();
        await montarEdicion(tester, repo: repo);
        await _escribir(tester, _telefono, '099 000 111');
        await tester.tap(_boton(_guardar));
        await tester.pump();

        await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: false);
        await tester.pump();
        final salio = await tester.binding.handlePopRoute();
        await tester.pump();

        expect(salio, isTrue);
        expect(find.text('Editar persona'), findsOneWidget);
        expect(find.text('¿Descartar lo que escribiste?'), findsNothing);

        repo.compuertaModificar!.complete();
        await asentar(tester);
        expect(find.text('Editar persona'), findsNothing);
      },
    );

    testWidgets('dado un guardado en curso, cuando se intenta escribir, los campos están '
        'bloqueados', (tester) async {
      final repo = PersonaRepositorioFalso()..compuertaModificar = Completer<void>();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await tester.tap(_boton(_guardar));
      await tester.pump();

      for (final c in [_nombre, _apellido, _telefono]) {
        expect(_textField(tester, c).readOnly, isTrue, reason: c);
      }

      repo.compuertaModificar!.complete();
      await asentar(tester);
    });

    testWidgets('dado un guardado en curso y el aviso «¿Es otra persona?», cuando se toca «Dar de '
        'baja y crear nueva», no pasa nada', (tester) async {
      final repo = PersonaRepositorioFalso()..compuertaModificar = Completer<void>();
      final resultado = await montarEdicion(
        tester,
        repo: repo,
        criterio: CriterioOtraPersonaFijo(),
      );
      await _cambioTotal(tester);
      await tester.tap(_boton(_guardarIgual));
      await tester.pump();

      await tester.tap(find.text(_bajaYNueva), warnIfMissed: false);
      await tester.pump();

      expect(resultado.cierres, 0);
      expect(repo.editadas, hasLength(1));

      repo.compuertaModificar!.complete();
      await asentar(tester);
      expect(resultado.resultado, isA<PersonaEditada>());
    });

    testWidgets('dado que se guardó y se vuelve a abrir, cuando reentra, el formulario muestra lo '
        'que quedó guardado', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);

      await tester.tap(find.text('abrir edición'));
      await asentar(tester);

      expect(find.text('099 000 111'), findsOneWidget);
      expect(find.text('098 765 432'), findsNothing);
      // Sin tocar nada, guardar de nuevo no escribe otra vez.
      await _tocar(tester, _guardar);
      expect(repo.editadas, hasLength(1));
    });

    testWidgets('dado que se descartó lo escrito y se vuelve a abrir, cuando reentra, el '
        'formulario tiene lo de antes', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      await tester.tap(find.text('Descartar'));
      await asentar(tester);

      await tester.tap(find.text('abrir edición'));
      await asentar(tester);

      expect(find.text('098 765 432'), findsOneWidget);
      expect(find.text('099 000 111'), findsNothing);
      expect(repo.editadas, isEmpty);
    });

    testWidgets('dado dos ediciones seguidas de la misma persona, cuando se guardan, la segunda '
        'parte de lo que dejó la primera', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);
      await tester.tap(find.text('abrir edición'));
      await asentar(tester);

      await _escribir(tester, _apellido, 'Gómez');
      await _tocar(tester, _guardar);

      expect(repo.editadas, hasLength(2));
      expect(repo.editadas[1].telefono, '099 000 111');
      expect(repo.editadas[1].apellido, 'Gómez');
    });
  });

  group('descartar lo escrito', () {
    testWidgets('dado un cambio sin guardar, cuando se toca la ✕, pregunta «¿Descartar lo que '
        'escribiste?» y «Seguir escribiendo» deja todo como está', (tester) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
      await tester.tap(find.text('Seguir escribiendo'));
      await asentar(tester);

      expect(find.text('Editar persona'), findsOneWidget);
      expect(find.text('099 000 111'), findsOneWidget);
      expect(repo.editadas, isEmpty);
    });

    testWidgets('dado un cambio sin guardar, cuando se elige «Descartar», cierra sin escribir ni '
        'avisar', (tester) async {
      final repo = PersonaRepositorioFalso();
      final resultado = await montarEdicion(tester, repo: repo);
      await _escribir(tester, _telefono, '099 000 111');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      await tester.tap(find.text('Descartar'));
      await asentar(tester);

      expect(resultado.resultado, isNull);
      expect(resultado.cierres, 1);
      expect(repo.editadas, isEmpty);
      expect(find.text(_cambiosGuardados), findsNothing);
      expect(find.text('Editar persona'), findsNothing);
    });

    testWidgets('dado un cambio sin guardar, cuando se usa el atrás del sistema, también '
        'pregunta', (tester) async {
      await montarEdicion(tester);
      await _escribir(tester, _nombre, 'Marta');

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
      expect(find.text('Editar persona'), findsOneWidget);
    });

    testWidgets('dado un cambio que se deshizo a mano, cuando se toca la ✕, cierra directo (no hay '
        'nada que perder)', (tester) async {
      final resultado = await montarEdicion(tester);
      await _escribir(tester, _telefono, '099 000 111');
      await _escribir(tester, _telefono, '098 765 432');

      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(resultado.cierres, 1);
    });

    testWidgets('dado que no se cambió nada, cuando se toca la ✕, cierra directo; un doble toque '
        'cierra una sola vez', (tester) async {
      final resultado = await montarEdicion(tester);

      final cerrar = find.byTooltip('Cerrar');
      await tester.tap(cerrar);
      await tester.tap(cerrar, warnIfMissed: false);
      await asentar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(resultado.cierres, 1);
      expect(find.text('abrir edición'), findsOneWidget);
    });

    testWidgets('dado el aviso de descartar abierto, cuando se toca la ✕ otra vez, no se abre un '
        'segundo aviso', (tester) async {
      await montarEdicion(tester);
      await _escribir(tester, _telefono, '099 000 111');

      // Dos toques sin fotograma en el medio: el segundo llega antes de que se abra el aviso.
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.tap(find.byTooltip('Cerrar'), warnIfMissed: false);
      await asentar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
    });
  });

  group('datos límite y texto grande', () {
    testWidgets(
      'dado un nombre y un apellido de 60 letras y un teléfono de 20, y el texto al 200 % '
      'en un teléfono chico, cuando se abre, no se desborda y se puede guardar',
      (tester) async {
        final repo = PersonaRepositorioFalso()
          ..contextos['per-1'] = contextoDeEdicion(
            nombre: 'N' * 60,
            apellido: 'A' * 60,
            telefono: '+598 99 123 456 7890',
          );
        await montarEdicion(tester, repo: repo, escala: 2, tamano: const Size(320, 568));

        await _escribir(tester, _telefono, '099 123 456');
        await _tocar(tester, _guardar);

        expect(tester.takeException(), isNull);
        expect(repo.editadas.single.nombre.length, 60);
        expect(repo.editadas.single.apellido.length, 60);
      },
    );

    testWidgets('dado un nombre pegado de más de 60 letras, cuando se guarda, se recorta al tope', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, 'N' * 100);
      await _escribir(tester, _apellido, 'A' * 100);
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.nombre.length, 60);
      expect(repo.editadas.single.apellido.length, 60);
    });

    testWidgets('dado un nombre pegado con saltos de línea, cuando se guarda, queda en una línea', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, 'Ana\nMaría');
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.nombre, isNot(contains('\n')));
    });

    testWidgets('dado un nombre con tildes, eñes y emoji, cuando se guarda, llega tal cual', (
      tester,
    ) async {
      final repo = PersonaRepositorioFalso();
      await montarEdicion(tester, repo: repo);

      await _escribir(tester, _nombre, 'Ñandú 🙂');
      await _escribir(tester, _apellido, "O'Brien-Núñez");
      await _tocar(tester, _guardar);

      expect(repo.editadas.single.nombre, 'Ñandú 🙂');
      expect(repo.editadas.single.apellido, "O'Brien-Núñez");
    });

    testWidgets(
      'dado un espacio que no se pudo leer, cuando se abre, la edición funciona igual sin '
      'la dirección',
      (tester) async {
        final repo = PersonaRepositorioFalso();
        await montarEdicion(tester, repo: repo, contexto: null);
        await _escribir(tester, _telefono, '099 000 111');
        await _tocar(tester, _guardar);

        expect(repo.editadas, hasLength(1));
      },
    );

    testWidgets('dado una persona sin espacio vigente, cuando se abre, no muestra dirección y el '
        'formulario funciona', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..contextos['per-1'] = contextoDeEdicion(espacioId: null);
      await montarEdicion(tester, repo: repo);

      expect(find.textContaining('Mataojo'), findsNothing);
      await _escribir(tester, _telefono, '099 000 111');
      await _tocar(tester, _guardar);

      expect(repo.editadas, hasLength(1));
    });

    testWidgets('dado el texto al 200 % y un error visible, cuando se muestra el formulario, no se '
        'desborda y el botón sigue a la vista y es tocable', (tester) async {
      await montarEdicion(tester, escala: 2);
      await _escribir(tester, _nombre, '');
      await _escribir(tester, _telefono, '099 12');

      await _tocar(tester, _guardar);

      expect(tester.takeException(), isNull);
      final boton = _boton(_guardar);
      expect(boton, findsOneWidget);
      expect(tester.getSize(boton).height, greaterThanOrEqualTo(52));
      expect(find.text('El nombre no puede quedar vacío.'), findsOneWidget);
    });
  });

  group('accesibilidad', () {
    testWidgets('dado el formulario, cuando se leen sus campos, cada uno tiene su nombre y el '
        'obligatorio lo dice', (tester) async {
      final handle = tester.ensureSemantics();
      await montarEdicion(tester);

      expect(find.bySemanticsLabel(RegExp('NOMBRE, obligatorio')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('TELÉFONO')), findsWidgets);
      expect(tester.getSemantics(find.byTooltip('Cerrar')).getSemanticsData().tooltip, 'Cerrar');
      handle.dispose();
    });

    testWidgets('dado el título, cuando se lee con el lector de pantalla, es un encabezado', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montarEdicion(tester);

      final datos = tester.getSemantics(find.text('Editar persona')).getSemanticsData();
      expect(datos.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });

    testWidgets(
      'dado el botón «Cerrar» y los de acción, cuando se miden, son de al menos 48 × 48',
      (tester) async {
        await montarEdicion(tester, criterio: CriterioOtraPersonaFijo());
        await _cambioTotal(tester);

        final cerrar = tester.getSize(find.byTooltip('Cerrar'));
        expect(cerrar.width, greaterThanOrEqualTo(48));
        expect(cerrar.height, greaterThanOrEqualTo(48));
        final enlace = tester.getSize(find.widgetWithText(TextButton, _bajaYNueva));
        expect(enlace.height, greaterThanOrEqualTo(48));
        expect(tester.getSize(_boton(_guardarIgual)).height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets('dado el aviso «¿Es otra persona?», cuando aparece, es una región viva que el '
        'lector anuncia', (tester) async {
      final handle = tester.ensureSemantics();
      await montarEdicion(tester, criterio: CriterioOtraPersonaFijo());

      await _cambioTotal(tester);

      final viva = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.liveRegion == true &&
            w.properties.label == null &&
            w.child != null,
      );
      expect(viva, findsWidgets);
      handle.dispose();
    });
  });

  test('dado un resultado de «Dar de baja y crear nueva», cuando se arma, lleva a la persona '
      'original y lo escrito', () {
    final original = contextoDeEdicion().persona;
    final r = DarDeBajaYCrearNuevaElegido(
      original: original,
      nombre: 'Roberto',
      apellido: 'Suárez',
      telefono: null,
    );

    expect(r.original, original);
    expect(r.telefono, isNull);
  });
}

/// Repositorio que lanza una excepción con datos personales adentro (la de Drift trae la sentencia).
final class _RepoQueLanza extends PersonaRepositorioFalso {
  @override
  Future<Either<Failure, ResultadoModificarPersona>> modificar({
    required String personaId,
    required String nombre,
    required String apellido,
    required String? telefono,
    required DateTime ahora,
  }) => throw StateError('UPDATE persona SET nombre = Fernández… 099 123 456');
}
