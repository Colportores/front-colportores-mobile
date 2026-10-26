import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/nota_persona.dart';
import '../providers/notas_persona_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import '../widgets/aviso_con_deshacer.dart';
import '../widgets/piezas_alta.dart';
import '../widgets/piezas_notas.dart';
import 'nota_persona_form_page.dart';
import 'notas_borradas_page.dart';

/// Las notas de una persona (HU-UBI-012, vista 32E, artboards E·01, E·03, E·04 y E·06): las notas de la
/// más nueva a la más vieja, con «+ Nueva nota» y, en cada una, sus opciones («Editar» y «Borrar»).
///
/// - El título y el aviso «Estas notas viven solo en tu celular.» (el texto de la HU) encabezan la lista;
///   solo «+ Nueva nota» queda fijo abajo.
/// - Borrar es un soft delete: la nota sale de la lista, aparece «Nota borrada.» con «Deshacer» y las
///   borradas se ven y se restauran desde «Ver borradas (n)» (E·05).
/// - Cargando, vacío (E·06), error al leer, persona que ya no está y persona en solo lectura (dada de
///   baja, o con su espacio dado de baja: 32B·04 y 32B·08) son estados propios. En solo lectura se ven
///   las notas, pero no hay «+ Nueva nota» ni opciones.
/// - Cada nota tiene su propia guarda: dos notas se pueden borrar una tras otra sin esperar a que
///   termine la primera, y un doble toque sobre la misma no la procesa dos veces.
///
/// Se abre desde la ficha de la persona (HU-UBI-009, #405), que todavía no existe: hoy
/// [NotasDePersonaPage.abrir] no tiene llamadores.
class NotasDePersonaPage extends ConsumerStatefulWidget {
  const NotasDePersonaPage({super.key, required this.personaId, required this.colportorId});

  final String personaId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las notas nuevas).
  final String colportorId;

  static Future<void> abrir(
    BuildContext context, {
    required String personaId,
    required String colportorId,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NotasDePersonaPage(personaId: personaId, colportorId: colportorId),
    ),
  );

  @override
  ConsumerState<NotasDePersonaPage> createState() => _NotasDePersonaPageState();
}

class _NotasDePersonaPageState extends ConsumerState<NotasDePersonaPage> {
  /// Ya se está abriendo algo (el formulario, las borradas o la hoja de opciones): un segundo toque no
  /// abre otro encima.
  var _abriendo = false;

  /// Las notas con un borrado en vuelo: un segundo toque sobre la misma no lo repite.
  final _borrando = <String>{};

  Future<void> _nueva() async {
    if (_abriendo) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendo = true;
    // Un aviso viejo («Nota borrada.») taparía el botón de abajo del formulario.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final guardada = await NotaPersonaFormPage.abrir(
        context,
        personaId: widget.personaId,
        colportorId: widget.colportorId,
      );
      if (!mounted || guardada == null) return;
      _avisarGuardada(guardada);
    } finally {
      _abriendo = false;
    }
  }

  void _avisarGuardada(NotaGuardada guardada) {
    mostrarAvisoDeNota(
      ScaffoldMessenger.of(context),
      mediaQuery: MediaQuery.of(context),
      texto: guardada.esNueva ? TextosNotas.guardada : TextosNotas.cambiosGuardados,
    );
  }

  Future<void> _abrirOpciones(NotaPersona nota, DateTime ahora) async {
    if (_abriendo) return;
    _abriendo = true;
    AccionNota? accion;
    try {
      accion = await HojaOpcionesNota.mostrar(
        context,
        titulo: FormatoNotas.tituloDelMenu(nota, ahora),
      );
    } finally {
      _abriendo = false;
    }
    if (!mounted || accion == null) return;
    switch (accion) {
      case AccionNota.editar:
        await _editar(nota);
      case AccionNota.borrar:
        await _borrar(nota);
    }
  }

  Future<void> _editar(NotaPersona nota) async {
    if (_abriendo) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendo = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final guardada = await NotaPersonaFormPage.abrir(
        context,
        personaId: widget.personaId,
        colportorId: widget.colportorId,
        nota: nota,
      );
      if (!mounted || guardada == null) return;
      _avisarGuardada(guardada);
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _borrar(NotaPersona nota) async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    await _correrBorrado(
      nota.id,
      borrar: ref.read(borrarNotaPersonaUseCaseProvider).call,
      restaurar: ref.read(restaurarNotaPersonaUseCaseProvider).call,
      mensajero: ScaffoldMessenger.of(context),
      mediaQuery: MediaQuery.of(context),
    );
  }

  /// Borra la nota [id] y muestra «Nota borrada.» con «Deshacer». Todo lo que hace falta después del
  /// `await` viene ya leído: el aviso sigue en pantalla aunque esta se cierre.
  Future<void> _correrBorrado(
    String id, {
    required Future<Either<Failure, NotaPersona>> Function(String) borrar,
    required Future<Either<Failure, NotaPersona>> Function(String) restaurar,
    required ScaffoldMessengerState mensajero,
    required MediaQueryData mediaQuery,
  }) async {
    if (!_borrando.add(id)) return;
    var salioBien = false;
    try {
      final resultado = await borrar(id);
      salioBien = resultado.isRight();
    } on Object {
      // Nada de la excepción al aviso: puede traer lo escrito (convenciones §7.5).
      salioBien = false;
    } finally {
      _borrando.remove(id);
    }
    if (salioBien) {
      mostrarAvisoConDeshacer(
        mensajero,
        mediaQuery: mediaQuery,
        texto: TextosNotas.borrada,
        etiquetaDeshacer: TextosNotas.deshacer,
        duracion: const Duration(seconds: 8),
        alDeshacer: () => _deshacer(id, restaurar, mensajero, mediaQuery),
      );
    } else {
      mostrarAvisoDeNota(
        mensajero,
        mediaQuery: mediaQuery,
        texto: TextosNotas.noPudimosBorrar,
        etiquetaAccion: TextosNotas.reintentar,
        alAccion: () => _correrBorrado(
          id,
          borrar: borrar,
          restaurar: restaurar,
          mensajero: mensajero,
          mediaQuery: mediaQuery,
        ),
      );
    }
  }

  Future<void> _deshacer(
    String id,
    Future<Either<Failure, NotaPersona>> Function(String) restaurar,
    ScaffoldMessengerState mensajero,
    MediaQueryData mediaQuery,
  ) async {
    var salioBien = false;
    try {
      salioBien = (await restaurar(id)).isRight();
    } on Object {
      salioBien = false;
    }
    if (salioBien) return;
    mostrarAvisoDeNota(
      mensajero,
      mediaQuery: mediaQuery,
      texto: TextosNotas.noPudimosDeshacer,
      etiquetaAccion: TextosNotas.reintentar,
      alAccion: () => _deshacer(id, restaurar, mensajero, mediaQuery),
    );
  }

  Future<void> _verBorradas() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await NotasBorradasPage.abrir(
        context,
        personaId: widget.personaId,
        colportorId: widget.colportorId,
      );
    } finally {
      _abriendo = false;
    }
  }

  void _reintentar() {
    ref
      ..invalidate(contextoNotasPersonaProvider(widget.personaId))
      ..invalidate(notasDePersonaProvider(widget.personaId));
  }

  @override
  Widget build(BuildContext context) {
    final contexto = ref.watch(contextoNotasPersonaProvider(widget.personaId));
    final notas = ref.watch(notasDePersonaProvider(widget.personaId));
    final datos = contexto.asData?.value;
    final noEncontrada = contexto.hasValue && datos == null;
    final soloLectura = datos?.soloLectura ?? false;
    final ahora = ref.watch(relojPersonaProvider)();

    final encabezado = EncabezadoNotas(
      titulo: datos == null ? TextosNotas.tituloGenerico : TextosNotas.titulo(datos.nombre),
    );
    final Widget cuerpo;
    if (contexto.hasError || notas.hasError) {
      cuerpo = _ConEncabezado(
        encabezado: encabezado,
        hijo: _ErrorDeLectura(nombre: datos?.nombre, alReintentar: _reintentar),
      );
    } else if (noEncontrada) {
      cuerpo = _ConEncabezado(
        encabezado: encabezado,
        hijo: const _Mensaje(texto: TextosNotas.personaNoEncontrada),
      );
    } else if (!contexto.hasValue || !notas.hasValue) {
      cuerpo = _ConEncabezado(encabezado: encabezado, hijo: const CargandoNotas());
    } else {
      final todas = notas.requireValue;
      cuerpo = _ListaDeNotas(
        encabezado: encabezado,
        activas: [
          for (final n in todas)
            if (!n.estaBorrada) n,
        ],
        cantidadBorradas: todas.where((n) => n.estaBorrada).length,
        ahora: ahora,
        alAbrirOpciones: soloLectura ? null : (n) => _abrirOpciones(n, ahora),
        alVerBorradas: _verBorradas,
        avisoSoloLectura: soloLectura ? TextosNotas.soloLectura(datos!.nombre) : null,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: CabeceraNotas(
                icono: Icons.chevron_left,
                tooltip: TextosNotas.volver,
                alTocar: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(child: cuerpo),
            if (datos != null && !soloLectura && notas.hasValue)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(
                  onPressed: _nueva,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: const Text(TextosNotas.nuevaNota, textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un estado que no es la lista (cargando, error, persona que no está): el encabezado y debajo el
/// estado, todo desplazable.
class _ConEncabezado extends StatelessWidget {
  const _ConEncabezado({required this.encabezado, required this.hijo});

  final Widget encabezado;
  final Widget hijo;

  @override
  Widget build(BuildContext context) => ListView(children: [encabezado, hijo]);
}

class _ListaDeNotas extends StatelessWidget {
  const _ListaDeNotas({
    required this.activas,
    required this.cantidadBorradas,
    required this.ahora,
    required this.alAbrirOpciones,
    required this.alVerBorradas,
    required this.avisoSoloLectura,
    required this.encabezado,
  });

  final Widget encabezado;

  /// El aviso de solo lectura, o `null` si se puede escribir. Va dentro de la lista: con el texto
  /// grande, fijo arriba le sacaría la pantalla a las notas.
  final String? avisoSoloLectura;

  final List<NotaPersona> activas;
  final int cantidadBorradas;
  final DateTime ahora;

  /// `null` en solo lectura: las notas se ven, pero no se tocan.
  final void Function(NotaPersona)? alAbrirOpciones;
  final VoidCallback alVerBorradas;

  @override
  Widget build(BuildContext context) {
    final hayBorradas = cantidadBorradas > 0;
    final aviso = avisoSoloLectura;
    final delante = aviso == null ? 1 : 2;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: delante + (activas.isEmpty ? 1 : activas.length) + (hayBorradas ? 1 : 0),
      itemBuilder: (context, indice) {
        if (indice == 0) return encabezado;
        if (aviso != null && indice == 1) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: AvisoAlta(
              color: ColoresAlta.ambarBorde,
              colorInsignia: ColoresAlta.ambar,
              glyph: '!',
              texto: aviso,
            ),
          );
        }
        final i = indice - delante;
        if (activas.isEmpty) {
          if (i == 0) {
            return const VacioNotas(titulo: TextosNotas.sinNotas, ayuda: TextosNotas.sinNotasAyuda);
          }
        } else if (i < activas.length) {
          final nota = activas[i];
          final abrir = alAbrirOpciones;
          return abrir == null
              ? _NotaDeSoloLectura(nota: nota, ahora: ahora)
              : TarjetaNota.activa(
                  key: ValueKey('nota_${nota.id}'),
                  nota: nota,
                  ahora: ahora,
                  alAbrirOpciones: () => abrir(nota),
                );
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: EnlaceAlta(
              texto: TextosNotas.verBorradas(cantidadBorradas),
              alPresionar: alVerBorradas,
            ),
          ),
        );
      },
    );
  }
}

/// Una nota en la vista de solo lectura: la misma tarjeta, sin opciones.
class _NotaDeSoloLectura extends StatelessWidget {
  const _NotaDeSoloLectura({required this.nota, required this.ahora});

  final NotaPersona nota;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) => TarjetaNota.soloLectura(nota: nota, ahora: ahora);
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AvisoAlta(
        color: ColoresAlta.ambarBorde,
        colorInsignia: ColoresAlta.ambar,
        glyph: '!',
        texto: texto,
      ),
    );
  }
}

class _ErrorDeLectura extends StatelessWidget {
  const _ErrorDeLectura({required this.nombre, required this.alReintentar});

  final String? nombre;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosNotas.noPudimosLeer(nombre),
        acciones: Align(
          alignment: Alignment.centerLeft,
          child: EnlaceAlta(texto: TextosNotas.reintentar, alPresionar: alReintentar),
        ),
      ),
    );
  }
}
