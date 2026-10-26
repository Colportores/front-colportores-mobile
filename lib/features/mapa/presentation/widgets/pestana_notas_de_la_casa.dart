import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/nota_ubicacion.dart';
import '../pages/nota_ubicacion_form_page.dart';
import '../pages/notas_borradas_del_lugar_page.dart';
import '../providers/notas_ubicacion_providers.dart';
import '../providers/personas_providers.dart';
import '../textos_notas.dart';
import 'piezas_alta.dart';
import 'piezas_notas.dart';
import 'piezas_persona.dart';

/// Las claves con que los tests (y el QA) encuentran lo que dibuja la pestaña Notas.
abstract final class ClavesNotasDelLugar {
  static const pestana = Key('notas_lugar_pestana');
  static const nueva = Key('notas_lugar_nueva');
  static const verBorradas = Key('notas_lugar_ver_borradas');
  static const aviso = Key('notas_lugar_aviso');
  static const soloLectura = Key('notas_lugar_solo_lectura');
  static const error = Key('notas_lugar_error');
  static const vacio = Key('notas_lugar_vacio');
  static const deshacer = Key('notas_lugar_deshacer');
  static Key nota(String id) => ValueKey('nota_lugar_$id');
}

/// Un aviso de la pestaña: lo último que pasó y, si hay algo para hacer, la acción.
class _AvisoDeNotas {
  const _AvisoDeNotas.exito(this.texto, {this.etiquetaAccion, this.alAccion})
    : color = ColoresAlta.verde,
      glyph = '✓';

  const _AvisoDeNotas.falla(this.texto, {this.etiquetaAccion, this.alAccion})
    : color = ColoresAlta.rojo,
      glyph = '!';

  final String texto;
  final Color color;
  final String glyph;
  final String? etiquetaAccion;
  final VoidCallback? alAccion;
}

/// La pestaña **Notas** de la hoja arriba de la casa (vista 39, C·05): las notas del lugar, cada una
/// con su fecha, de la más nueva a la más vieja, y «+ Nota del lugar». Un lugar tiene todas las que
/// quiera (decisión de Cristian, 23/10, «Notas casa»); las de cada visita van en el historial y las de
/// cada persona en su ficha.
///
/// - El aviso «Estas notas viven solo en tu celular.» se puede esconder con «No volver a mostrar»
///   (decisión de Cristian, 23/10, «Aviso privado»); se vuelve a encender desde Configuración.
/// - Tocar una nota abre sus opciones («Editar» y «Borrar»). Borrar es un soft delete: la nota sale de
///   la lista, el aviso de la pestaña dice «Nota borrada.» con «Deshacer», y las borradas se ven y se
///   restauran desde «Ver borradas (n)». Nada se pierde del teléfono.
/// - Cargando, vacío, error al leer y lugar dado de baja (solo lectura: se leen, no se tocan) son
///   estados propios. Sin conexión funciona igual: las notas nunca suben.
/// - Los avisos van **en la pestaña** y no en un `SnackBar`: la hoja puede ser una ruta modal que
///   taparía el aviso del `Scaffold` de abajo. Hay uno a la vez; el último reemplaza al anterior.
/// - Cada nota tiene su propia guarda: dos notas se pueden borrar una tras otra sin esperar a que
///   termine la primera, y un doble toque sobre la misma no la procesa dos veces.
///
/// **local-only — PII**: el texto vive solo en el teléfono y nunca va a un log.
class PestanaNotasDeLaCasa extends ConsumerStatefulWidget {
  const PestanaNotasDeLaCasa({
    super.key,
    required this.ubicacionId,
    required this.colportorId,
    required this.soloLectura,
  });

  final String ubicacionId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las notas nuevas). Sin él no se escribe.
  final String? colportorId;

  /// El lugar está dado de baja: las notas se ven, pero no se agregan, editan ni borran.
  final bool soloLectura;

  @override
  ConsumerState<PestanaNotasDeLaCasa> createState() => _PestanaNotasDeLaCasaState();
}

class _PestanaNotasDeLaCasaState extends ConsumerState<PestanaNotasDeLaCasa> {
  /// Ya se está abriendo algo (el formulario, las borradas o la hoja de opciones): un segundo toque no
  /// abre otro encima. Es un campo: corta aunque el toque llegue antes de que se vuelva a dibujar.
  var _abriendo = false;

  /// Las notas con un borrado en vuelo: un segundo toque sobre la misma no lo repite.
  final _borrando = <String>{};

  _AvisoDeNotas? _aviso;

  bool get _puedeEscribir => !widget.soloLectura && widget.colportorId != null;

  void _avisar(_AvisoDeNotas? aviso) {
    if (mounted) setState(() => _aviso = aviso);
  }

  Future<void> _nueva() async {
    final colportorId = widget.colportorId;
    if (_abriendo || colportorId == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendo = true;
    try {
      final guardada = await NotaUbicacionFormPage.abrir(
        context,
        ubicacionId: widget.ubicacionId,
        colportorId: colportorId,
      );
      if (guardada != null) _avisarGuardada(guardada);
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _editar(NotaUbicacion nota) async {
    final colportorId = widget.colportorId;
    if (_abriendo || colportorId == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendo = true;
    try {
      final guardada = await NotaUbicacionFormPage.abrir(
        context,
        ubicacionId: widget.ubicacionId,
        colportorId: colportorId,
        nota: nota,
      );
      if (guardada != null) _avisarGuardada(guardada);
    } finally {
      _abriendo = false;
    }
  }

  void _avisarGuardada(NotaDelLugarGuardada guardada) => _avisar(
    _AvisoDeNotas.exito(guardada.esNueva ? TextosNotas.guardada : TextosNotas.cambiosGuardados),
  );

  Future<void> _abrirOpciones(NotaUbicacion nota, DateTime ahora) async {
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

  Future<void> _borrar(NotaUbicacion nota) async {
    if (frenaPorCuentaRestringida(context, ref)) return;
    final id = nota.id;
    if (!_borrando.add(id)) return;
    final borrar = ref.read(borrarNotaUbicacionUseCaseProvider);
    var salioBien = false;
    try {
      salioBien = (await borrar(id)).isRight();
    } on Object {
      // Nada de la excepción al aviso: puede traer lo escrito (convenciones §7.5).
      salioBien = false;
    } finally {
      _borrando.remove(id);
    }
    _avisar(
      salioBien
          ? _AvisoDeNotas.exito(
              TextosNotas.borrada,
              etiquetaAccion: TextosNotas.deshacer,
              alAccion: () => _deshacer(id),
            )
          : _AvisoDeNotas.falla(
              TextosNotas.noPudimosBorrar,
              etiquetaAccion: TextosNotas.reintentar,
              alAccion: () => _borrar(nota),
            ),
    );
  }

  Future<void> _deshacer(String id) async {
    if (!_borrando.add(id)) return;
    final restaurar = ref.read(restaurarNotaUbicacionUseCaseProvider);
    var salioBien = false;
    try {
      salioBien = (await restaurar(id)).isRight();
    } on Object {
      salioBien = false;
    } finally {
      _borrando.remove(id);
    }
    _avisar(
      salioBien
          ? const _AvisoDeNotas.exito(TextosNotas.restaurada)
          : _AvisoDeNotas.falla(
              TextosNotas.noPudimosDeshacer,
              etiquetaAccion: TextosNotas.reintentar,
              alAccion: () => _deshacer(id),
            ),
    );
  }

  Future<void> _verBorradas() async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      await NotasBorradasDelLugarPage.abrir(
        context,
        ubicacionId: widget.ubicacionId,
        colportorId: widget.colportorId,
        puedeRestaurar: _puedeEscribir,
      );
    } finally {
      _abriendo = false;
    }
  }

  void _reintentarLectura() => ref.invalidate(notasDeUbicacionProvider(widget.ubicacionId));

  @override
  Widget build(BuildContext context) {
    final notas = ref.watch(notasDeUbicacionProvider(widget.ubicacionId));
    final ahora = ref.watch(relojPersonaProvider)();
    final aviso = _aviso;

    final List<Widget> cuerpo;
    if (notas.hasError) {
      cuerpo = [
        AvisoAlta(
          key: ClavesNotasDelLugar.error,
          color: ColoresAlta.rojo,
          glyph: '!',
          texto: TextosNotas.noPudimosLeerDelLugar,
          acciones: Align(
            alignment: Alignment.centerLeft,
            child: EnlaceAlta(texto: TextosNotas.reintentar, alPresionar: _reintentarLectura),
          ),
        ),
      ];
    } else if (!notas.hasValue) {
      cuerpo = const [CargandoNotas(horizontal: 0)];
    } else {
      final todas = notas.requireValue;
      final activas = [
        for (final n in todas)
          if (!n.estaBorrada) n,
      ];
      final borradas = todas.length - activas.length;
      cuerpo = [
        if (activas.isEmpty)
          const VacioNotas(
            key: ClavesNotasDelLugar.vacio,
            titulo: TextosNotas.sinNotas,
            ayuda: TextosNotas.sinNotasAyuda,
            horizontal: 0,
          ),
        for (final nota in activas)
          if (_puedeEscribir)
            TarjetaNota.activa(
              key: ClavesNotasDelLugar.nota(nota.id),
              nota: nota,
              ahora: ahora,
              conLapiz: true,
              margen: EdgeInsets.zero,
              alAbrirOpciones: () => _abrirOpciones(nota, ahora),
            )
          else
            TarjetaNota.soloLectura(
              key: ClavesNotasDelLugar.nota(nota.id),
              nota: nota,
              ahora: ahora,
              conLapiz: true,
              margen: EdgeInsets.zero,
            ),
        if (_puedeEscribir) _EnlaceDeLaPestana(texto: TextosNotas.notaDelLugar, alTocar: _nueva),
        if (borradas > 0)
          _EnlaceDeLaPestana(
            texto: TextosNotas.verBorradas(borradas),
            alTocar: _verBorradas,
            clave: ClavesNotasDelLugar.verBorradas,
          ),
      ];
    }

    return Column(
      key: ClavesNotasDelLugar.pestana,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        AvisoPrivacidadPersona(colportorId: widget.colportorId, texto: TextosNotas.privacidad),
        if (widget.soloLectura)
          const AvisoAlta(
            key: ClavesNotasDelLugar.soloLectura,
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: TextosNotas.soloLecturaDelLugar,
          ),
        if (aviso != null)
          AvisoAlta(
            key: ClavesNotasDelLugar.aviso,
            color: aviso.color,
            glyph: aviso.glyph,
            texto: aviso.texto,
            acciones: aviso.etiquetaAccion == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: EnlaceAlta(
                      key: ClavesNotasDelLugar.deshacer,
                      texto: aviso.etiquetaAccion!,
                      alPresionar: aviso.alAccion,
                    ),
                  ),
          ),
        ...cuerpo,
      ],
    );
  }
}

/// Un enlace de la pestaña («+ Nota del lugar», «Ver borradas (n)»): texto azul de 13,5 con un objetivo
/// táctil de 48 dp (canvas, `Bloques` · text).
class _EnlaceDeLaPestana extends StatelessWidget {
  const _EnlaceDeLaPestana({required this.texto, required this.alTocar, this.clave});

  final String texto;
  final VoidCallback alTocar;
  final Key? clave;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: texto,
      onTap: alTocar,
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InkWell(
          key: clave ?? ClavesNotasDelLugar.nueva,
          borderRadius: BorderRadius.circular(8),
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text(
                  texto,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ColoresAlta.azul,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
