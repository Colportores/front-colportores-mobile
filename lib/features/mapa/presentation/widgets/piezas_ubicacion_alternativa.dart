import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/estado_ubicacion_alternativa.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../textos_ubicacion_alternativa.dart';
import 'piezas_alta.dart';
import 'piezas_ficha_persona.dart' show RotuloDeSeccion;
import 'piezas_lista_ubicaciones.dart' show textoGrande;

// Las piezas de la ubicación alternativa de cobranza (HU-UBI-013, vista 22 grupo A): la tarjeta de
// la ficha y de las filas del selector, y la sección «COBRANZA» de la ficha.

/// Claves para los tests.
abstract final class ClavesAlternativa {
  static const seccion = Key('alternativa_seccion');
  static const cargando = Key('alternativa_cargando');
  static const errorLectura = Key('alternativa_error_lectura');
  static const reintentarLectura = Key('alternativa_reintentar_lectura');
  static const sinAlternativa = Key('alternativa_sin');
  static const vigente = Key('alternativa_vigente');
  static const deBaja = Key('alternativa_de_baja');
  static const faltante = Key('alternativa_faltante');
  static const guardando = Key('alternativa_guardando');
  static const elegir = Key('alternativa_elegir');
  static const quitar = Key('alternativa_quitar');
  static const avisoDeBaja = Key('alternativa_aviso_de_baja');
  static const elegirOtra = Key('alternativa_elegir_otra');
  static const errorAlGuardar = Key('alternativa_error_al_guardar');
  static const reintentarGuardar = Key('alternativa_reintentar_guardar');

  // El selector.
  static const selector = Key('alternativa_selector');
  static const selectorCerrar = Key('alternativa_selector_cerrar');
  static const selectorBuscar = Key('alternativa_selector_buscar');
  static const selectorBorrarBusqueda = Key('alternativa_selector_borrar_busqueda');
  static const selectorCargando = Key('alternativa_selector_cargando');
  static const selectorError = Key('alternativa_selector_error');
  static const selectorReintentar = Key('alternativa_selector_reintentar');
  static const selectorVacio = Key('alternativa_selector_vacio');
  static const selectorSinResultados = Key('alternativa_selector_sin_resultados');
  static const selectorRegistrar = Key('alternativa_selector_registrar');
  static const selectorRegistrarMas = Key('alternativa_selector_registrar_mas');
  static const selectorRotulo = Key('alternativa_selector_rotulo');

  static Key fila(String ubicacionId) => Key('alternativa_fila_$ubicacionId');

  // La hoja de quitar.
  static const hojaQuitar = Key('alternativa_hoja_quitar');
  static const hojaQuitarConfirmar = Key('alternativa_hoja_quitar_confirmar');
  static const hojaQuitarCancelar = Key('alternativa_hoja_quitar_cancelar');
  static const hojaQuitarError = Key('alternativa_hoja_quitar_error');
}

/// El glifo de cada tipo de ubicación (el de la Lista y el del canvas 22A·02).
String glifoDelTipo(TipoUbicacion tipo) => switch (tipo) {
  TipoUbicacion.casa => '⌂',
  TipoUbicacion.negocio => '▤',
  TipoUbicacion.edificio => '▦',
};

/// La tarjeta de la ubicación alternativa (canvas 22A): un glifo, un rótulo opcional, el título y el
/// detalle, y a la derecha una acción o la flecha. Con [alTocar] la tarjeta entera es un botón (las
/// filas del selector y «Cobrar en otro lugar»); sin él, la acción de [derecha] es la única tocable.
///
/// Con el texto agrandado (desde 1,4×) la acción baja debajo del texto en vez de apretarlo.
class TarjetaAlternativa extends StatelessWidget {
  const TarjetaAlternativa({
    super.key,
    required this.glifo,
    required this.titulo,
    this.rotulo,
    this.detalle,
    this.detalle2,
    this.derecha,
    this.alTocar,
    this.etiquetaSemantica,
    this.destacada = false,
    this.atenuada = false,
    this.tachada = false,
  });

  final String glifo;
  final String titulo;

  /// «SE COBRA ACÁ», «DADA DE BAJA»: encima del título.
  final String? rotulo;
  final String? detalle;

  /// La tercera línea: «a 1,2 km».
  final String? detalle2;

  /// A la derecha del texto: un botón o la flecha.
  final Widget? derecha;
  final VoidCallback? alTocar;

  /// Lo que dice el lector de pantalla de la tarjeta entera (si no, junta lo que se ve).
  final String? etiquetaSemantica;

  /// El glifo en azul (la alternativa vigente) en vez de gris.
  final bool destacada;

  /// La alternativa dada de baja: apagada y con la dirección tachada.
  final bool atenuada;
  final bool tachada;

  @override
  Widget build(BuildContext context) {
    final apilada = textoGrande(context);
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rotulo != null)
          Text(
            rotulo!,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 1.2,
              color: tachada ? ColoresAlta.rojo : ColoresAlta.azul,
              fontWeight: FontWeight.w500,
            ),
          ),
        Text(
          titulo,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ColoresAlta.tinta,
            decoration: tachada ? TextDecoration.lineThrough : null,
          ),
        ),
        if (detalle != null)
          Text(
            detalle!,
            style: const TextStyle(fontSize: 13, color: ColoresAlta.gris, height: 1.35),
          ),
        if (detalle2 != null)
          Text(
            detalle2!,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
              color: ColoresAlta.gris,
            ),
          ),
      ],
    );
    final glifoCaja = ExcludeSemantics(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: destacada ? ColoresAlta.azul : ColoresAlta.grisFondo,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          glifo,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: destacada ? Colors.white : ColoresAlta.tinta,
          ),
        ),
      ),
    );
    final cuerpoDelTexto = etiquetaSemantica == null
        ? texto
        : Semantics(label: etiquetaSemantica, excludeSemantics: true, child: texto);
    final contenido = apilada
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  glifoCaja,
                  const SizedBox(width: 12),
                  Expanded(child: cuerpoDelTexto),
                ],
              ),
              if (derecha != null) Align(alignment: Alignment.centerRight, child: derecha),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              glifoCaja,
              const SizedBox(width: 12),
              Expanded(child: cuerpoDelTexto),
              if (derecha != null) ...[const SizedBox(width: 8), derecha!],
            ],
          );
    final tarjeta = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: destacada ? ColoresAlta.azul : ColoresAlta.grisBorde),
      ),
      child: contenido,
    );
    final atenuacion = atenuada ? Opacity(opacity: .6, child: tarjeta) : tarjeta;
    if (alTocar == null) return atenuacion;
    return Semantics(
      button: true,
      container: true,
      child: InkWell(onTap: alTocar, borderRadius: BorderRadius.circular(14), child: atenuacion),
    );
  }
}

/// La acción de texto de la derecha de una tarjeta («Elegir», «Quitar»): con el alto de un objetivo
/// táctil.
class AccionDeTarjeta extends StatelessWidget {
  const AccionDeTarjeta({
    super.key,
    required this.texto,
    required this.alTocar,
    this.color = ColoresAlta.azul,
    this.etiquetaSemantica,
  });

  final String texto;
  final VoidCallback? alTocar;
  final Color color;
  final String? etiquetaSemantica;

  @override
  Widget build(BuildContext context) {
    final boton = TextButton(
      onPressed: alTocar,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(texto, textAlign: TextAlign.center),
    );
    if (etiquetaSemantica == null) return boton;
    return Semantics(
      container: true,
      label: etiquetaSemantica,
      button: true,
      enabled: alTocar != null,
      onTap: alTocar,
      excludeSemantics: true,
      child: boton,
    );
  }
}

/// Lo que muestra la sección «COBRANZA» de la ficha, ya resuelto por quien la dibuja.
class SeccionCobranzaAlternativa extends StatelessWidget {
  const SeccionCobranzaAlternativa({
    super.key,
    required this.nombre,
    required this.lectura,
    required this.soloLectura,
    required this.guardando,
    required this.alElegir,
    required this.alQuitar,
    required this.alReintentarLectura,
    this.falla,
  });

  /// El nombre de pila de la persona.
  final String nombre;

  /// Dónde se le cobra, al día. Mientras llega el primer dato, cargando.
  final AsyncValue<EstadoUbicacionAlternativa> lectura;

  /// La persona o su depto están de baja (32B·04 y 32B·08): se ve, no se cambia.
  final bool soloLectura;

  /// Se está escribiendo la alternativa: nada se puede tocar.
  final bool guardando;

  /// Abre el selector (22A·02); `null` = apagado (ya se está abriendo algo).
  final VoidCallback? alElegir;

  /// Abre la hoja de quitar (22A·07) de la alternativa que se ve ahora; `null` = apagado.
  final VoidCallback? alQuitar;
  final VoidCallback alReintentarLectura;

  /// El aviso de que no se pudo guardar (22A·09), con su acción.
  final FallaAlternativa? falla;

  @override
  Widget build(BuildContext context) {
    final estado = lectura.value;
    // En solo lectura no hay nada que ofrecer: sin alternativa la sección no está.
    if (soloLectura && (estado == null || estado is SinUbicacionAlternativa)) {
      return const SizedBox.shrink();
    }
    final hijos = <Widget>[
      const RotuloDeSeccion(texto: TextosUbicacionAlternativa.rotuloSeccion),
      const SizedBox(height: 6),
      if (falla != null && !soloLectura) ...[
        _AvisoDeFalla(falla: falla!, ocupado: guardando),
        const SizedBox(height: 10),
      ],
      ..._cuerpo(context, estado),
    ];
    return Column(
      key: ClavesAlternativa.seccion,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: hijos,
    );
  }

  List<Widget> _cuerpo(BuildContext context, EstadoUbicacionAlternativa? estado) {
    if (estado == null) {
      if (lectura.hasError) {
        return [
          KeyedSubtree(
            key: ClavesAlternativa.errorLectura,
            child: AvisoAlta(
              color: ColoresAlta.rojo,
              glyph: '!',
              texto: TextosUbicacionAlternativa.noPudimosLeer(nombre),
              acciones: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: ClavesAlternativa.reintentarLectura,
                  onPressed: alReintentarLectura,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: ColoresAlta.azul,
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: const Text(TextosUbicacionAlternativa.reintentar),
                ),
              ),
            ),
          ),
        ];
      }
      return [
        Semantics(
          key: ClavesAlternativa.cargando,
          liveRegion: true,
          label: TextosUbicacionAlternativa.cargando(nombre),
          child: ExcludeSemantics(
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: ColoresAlta.grisFondo.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ];
    }
    if (guardando) {
      return [
        const TarjetaAlternativa(
          key: ClavesAlternativa.guardando,
          glifo: '⇢',
          titulo: TextosUbicacionAlternativa.sinAlternativaTitulo,
          detalle: TextosUbicacionAlternativa.guardando,
          derecha: ExcludeSemantics(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ];
    }
    return switch (estado) {
      SinUbicacionAlternativa() => [
        TarjetaAlternativa(
          key: ClavesAlternativa.sinAlternativa,
          glifo: '⇢',
          titulo: TextosUbicacionAlternativa.sinAlternativaTitulo,
          detalle: TextosUbicacionAlternativa.sinAlternativaDetalle,
          derecha: const Text(
            TextosUbicacionAlternativa.elegir,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ColoresAlta.azul),
          ),
          alTocar: alElegir,
        ),
      ],
      UbicacionAlternativaVigente(:final ubicacion) => [
        TarjetaAlternativa(
          key: ClavesAlternativa.vigente,
          glifo: '\$',
          destacada: true,
          rotulo: TextosUbicacionAlternativa.seCobraAca,
          titulo: FormatoUbicaciones.direccion(ubicacion),
          detalle: FormatoUbicaciones.tipo(ubicacion.tipo),
          derecha: soloLectura
              ? null
              : AccionDeTarjeta(
                  key: ClavesAlternativa.quitar,
                  texto: TextosUbicacionAlternativa.quitarAccion,
                  color: ColoresAlta.rojo,
                  alTocar: alQuitar,
                  etiquetaSemantica: TextosUbicacionAlternativa.semanticaQuitar(
                    FormatoUbicaciones.direccion(ubicacion),
                  ),
                ),
        ),
      ],
      UbicacionAlternativaDeBaja(:final ubicacion) => [
        KeyedSubtree(
          key: ClavesAlternativa.avisoDeBaja,
          child: AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: TextosUbicacionAlternativa.avisoDeBajaCanvas,
            acciones: soloLectura
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: ClavesAlternativa.elegirOtra,
                      onPressed: alElegir,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: ColoresAlta.azul,
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: const Text(TextosUbicacionAlternativa.elegirOtra),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        TarjetaAlternativa(
          key: ClavesAlternativa.deBaja,
          glifo: '\$',
          destacada: true,
          atenuada: true,
          tachada: true,
          rotulo: TextosUbicacionAlternativa.dadaDeBajaRotulo,
          titulo: ubicacion == null
              ? TextosUbicacionAlternativa.faltanteTitulo
              : FormatoUbicaciones.direccion(ubicacion),
          detalle: ubicacion == null ? null : FormatoUbicaciones.tipo(ubicacion.tipo),
          derecha: soloLectura
              ? null
              : AccionDeTarjeta(
                  key: ClavesAlternativa.quitar,
                  texto: TextosUbicacionAlternativa.quitarAccion,
                  color: ColoresAlta.rojo,
                  alTocar: alQuitar,
                  etiquetaSemantica: TextosUbicacionAlternativa.semanticaQuitar(
                    ubicacion == null ? '' : FormatoUbicaciones.direccion(ubicacion),
                  ).trim(),
                ),
        ),
      ],
      UbicacionAlternativaFaltante() => [
        KeyedSubtree(
          key: ClavesAlternativa.faltante,
          child: AvisoAlta(
            color: ColoresAlta.ambarBorde,
            colorInsignia: ColoresAlta.ambar,
            glyph: '!',
            texto: TextosUbicacionAlternativa.avisoFaltante,
            acciones: soloLectura
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          key: ClavesAlternativa.elegirOtra,
                          onPressed: alElegir,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: ColoresAlta.azul,
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          child: const Text(TextosUbicacionAlternativa.elegirOtra),
                        ),
                        TextButton(
                          key: ClavesAlternativa.quitar,
                          onPressed: alQuitar,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: ColoresAlta.rojo,
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          child: const Text(TextosUbicacionAlternativa.quitarAccion),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    };
  }
}

/// Por qué no se pudo guardar la alternativa (22A·09) y qué se puede hacer: reintentar con la misma
/// ubicación o, si la que se eligió ya no sirve (el aviso lo dice), tocar «Elegir» de nuevo.
class FallaAlternativa {
  const FallaAlternativa({required this.texto, required this.reintentar});

  final String texto;

  /// Vuelve a guardar la misma ubicación; `null` = no tiene sentido repetirlo.
  final VoidCallback? reintentar;
}

class _AvisoDeFalla extends StatelessWidget {
  const _AvisoDeFalla({required this.falla, required this.ocupado});

  final FallaAlternativa falla;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    final botones = <Widget>[
      if (falla.reintentar != null)
        TextButton(
          key: ClavesAlternativa.reintentarGuardar,
          onPressed: ocupado ? null : falla.reintentar,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: ColoresAlta.azul,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: const Text(TextosUbicacionAlternativa.reintentar),
        ),
    ];
    return KeyedSubtree(
      key: ClavesAlternativa.errorAlGuardar,
      child: AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: falla.texto,
        acciones: botones.isEmpty
            ? null
            : Align(
                alignment: Alignment.centerRight,
                child: Wrap(alignment: WrapAlignment.end, children: botones),
              ),
      ),
    );
  }
}
