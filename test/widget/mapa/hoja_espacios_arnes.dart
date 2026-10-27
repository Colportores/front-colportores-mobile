// Arnés de los tests de la hoja de una ubicación y de la gestión de sus deptos (vista 11, HU-UBI-007):
// monta la hoja real sobre un anfitrión que la abre, con los repositorios en memoria de
// `espacios_falsos.dart`, y deja a mano las búsquedas más usadas.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

/// Lo que un test de la hoja necesita después de montarla.
final class MontajeHoja {
  MontajeHoja({required this.repo, required this.ubicaciones, required this.contador});

  final EspacioRepoFalso repo;
  final RepoEdicionFalso ubicaciones;
  final ContadorPersonasFalso contador;

  /// Cómo se cerró cada vez que se abrió la hoja (`null`: el colportor la cerró sin hacer nada).
  final salidas = <SalidaModificarUbicacion?>[];

  /// Las ubicaciones cuya edición (vista 07) se abrió desde «Editar edificio».
  final ediciones = <String>[];

  /// Qué devuelve la edición al cerrarse. Con [esperaEdicion] se queda abierta hasta completarla.
  SalidaModificarUbicacion? salidaEdicion;
  Completer<SalidaModificarUbicacion?>? esperaEdicion;

  /// Los ids que genera el alta, en orden.
  final idsGenerados = <String>[];

  Future<SalidaModificarUbicacion?> abrirEdicion(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
    bool ofreceIrALaCobranza = false,
  }) async {
    ediciones.add(ubicacionId);
    final espera = esperaEdicion;
    if (espera != null) return espera.future;
    return salidaEdicion;
  }
}

class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.montaje, required this.ubicacionId, this.distancia});

  final MontajeHoja montaje;
  final String ubicacionId;
  final double? distancia;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => montaje.salidas.add(
            await mostrarHojaUbicacion(
              context,
              colportorId: 'col-1',
              ubicacionId: ubicacionId,
              distanciaMetros: distancia,
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

/// Deja correr los futuros y las animaciones de la hoja.
Future<void> asentarHoja(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Monta la hoja de [ubicacion] (por defecto, el edificio de Mataojo 2044) con [espacios] y la abre.
///
/// [personas] son las personas activas de cada espacio. [escala] es el tamaño de texto del sistema.
Future<MontajeHoja> montarHoja(
  WidgetTester tester, {
  Ubicacion? ubicacion,
  List<Espacio> espacios = const [],
  Map<String, int>? personas,
  double escala = 1,
  Size tamano = const Size(390, 844),
  double? distancia = 25,
  bool abrir = true,
  List<Override> extras = const [],
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final u = ubicacion ?? edificioMataojo();
  final montaje = MontajeHoja(
    repo: EspacioRepoFalso(u, espacios: espacios),
    ubicaciones: RepoEdicionFalso(u),
    contador: ContadorPersonasFalso(personas),
  );
  var secuencia = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ubicacionRepositoryProvider.overrideWithValue(montaje.ubicaciones),
        espacioRepositoryProvider.overrideWithValue(montaje.repo),
        contadorPersonasEspacioProvider.overrideWithValue(montaje.contador),
        generadorIdEspacioProvider.overrideWithValue(() {
          final id = 'nuevo-${++secuencia}';
          montaje.idsGenerados.add(id);
          return id;
        }),
        relojEspaciosProvider.overrideWithValue(() => hoyEspacios),
        abridorEdicionUbicacionProvider.overrideWithValue(montaje.abrirEdicion),
        ...extras,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(montaje: montaje, ubicacionId: u.id, distancia: distancia),
      ),
    ),
  );
  if (abrir) {
    await abrirLaHoja(tester);
  }
  return montaje;
}

/// Toca «abrir» y deja que la hoja termine de subir y de leer.
Future<void> abrirLaHoja(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await asentarHoja(tester);
}

// ---------------------------------------------------------------- búsquedas

final hojaUbicacion = find.byKey(ClavesHojaUbicacion.hoja);
final botonAgregarDepto = find.byKey(ClavesHojaUbicacion.agregarDepto);
final botonEditarUbicacion = find.byKey(ClavesHojaUbicacion.editar);
final cerrarHojaUbicacion = find.byKey(ClavesHojaUbicacion.cerrar);
Finder filaDepto(String id) => find.byKey(ClavesHojaUbicacion.fila(id));

final hojaDepto = find.byKey(ClavesHojaDepto.hoja);
final campoNumero = find.descendant(
  of: find.byKey(ClavesHojaDepto.numero),
  matching: find.byType(TextField),
);
final campoPiso = find.descendant(
  of: find.byKey(ClavesHojaDepto.piso),
  matching: find.byType(TextField),
);
final botonAgregar = find.byKey(ClavesHojaDepto.agregar);
final botonAgregarYCargarOtro = find.byKey(ClavesHojaDepto.agregarYCargarOtro);
final botonGuardarDepto = find.byKey(ClavesHojaDepto.guardar);
final botonDarDeBaja = find.byKey(ClavesHojaDepto.darDeBaja);
final avisoRepetido = find.byKey(ClavesHojaDepto.repetido);
final enlaceVerRepetido = find.byKey(ClavesHojaDepto.verRepetido);
final avisoFalla = find.byKey(ClavesHojaDepto.falla);

/// ¿Está habilitado el botón [boton] (un `FilledButton`, `OutlinedButton` o `TextButton`)?
bool habilitado(WidgetTester tester, Finder boton) {
  final widget = tester.widget(boton);
  return switch (widget) {
    FilledButton(:final onPressed) => onPressed != null,
    OutlinedButton(:final onPressed) => onPressed != null,
    TextButton(:final onPressed) => onPressed != null,
    _ => throw StateError('no es un botón: ${widget.runtimeType}'),
  };
}

/// Escribe en un campo de la hoja del depto.
Future<void> escribir(WidgetTester tester, Finder campo, String texto) async {
  await tester.enterText(campo, texto);
  await tester.pump();
}

/// Toca «+ Departamento» y deja que suba la hoja del alta.
Future<void> abrirAltaDepto(WidgetTester tester) async {
  await tester.tap(botonAgregarDepto);
  await asentarHoja(tester);
}

/// Toca la fila del depto [id] y deja que suba la hoja de su edición.
Future<void> abrirEdicionDepto(WidgetTester tester, String id) async {
  await tester.tap(filaDepto(id));
  await asentarHoja(tester);
}

/// Lo que hay escrito en un campo.
String textoDe(WidgetTester tester, Finder campo) =>
    tester.widget<TextField>(campo).controller!.text;
