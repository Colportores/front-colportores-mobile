import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/nota_de_texto.dart';
import '../textos_notas.dart';
import 'aviso_con_deshacer.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart' show textoGrande;
import 'piezas_persona.dart';

// Las piezas de las pantallas de notas (vista 32E): la cabecera, la tarjeta de una nota y la hoja de
// opciones.

/// Claves para los tests.
abstract final class ClavesNotas {
  static const hojaOpciones = Key('notas_hoja_opciones');
  static const botonEditar = Key('notas_opcion_editar');
  static const botonBorrar = Key('notas_opcion_borrar');
  static const campo = Key('notas_campo');
}

/// La fila de arriba: el botón de atrás o de cerrar y el rótulo «NOTAS».
class CabeceraNotas extends StatelessWidget {
  const CabeceraNotas({
    super.key,
    required this.icono,
    required this.tooltip,
    required this.alTocar,
  });

  final IconData icono;
  final String tooltip;

  /// `null` apaga el botón (mientras se guarda).
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 14, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: tooltip,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: alTocar,
            icon: Icon(icono, size: 28),
          ),
          Expanded(
            child: Text(
              TextosNotas.rotulo,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
                color: navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El título «Notas de María» (o «Nueva nota»): un encabezado para el lector de pantalla.
class TituloNotas extends StatelessWidget {
  const TituloNotas({super.key, required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          header: true,
          child: Text(titulo, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ),
    );
  }
}

/// Lo de arriba de la lista: el título y el aviso «Estas notas viven solo en tu celular.». Va **dentro**
/// de lo que se desplaza: con el texto al 200 % en un teléfono chico, fijo le sacaría la pantalla a las
/// notas.
class EncabezadoNotas extends StatelessWidget {
  const EncabezadoNotas({super.key, required this.titulo, required this.colportorId});

  final String titulo;

  /// UUID del usuario con la sesión iniciada: el aviso se puede esconder y la preferencia es suya.
  /// Sin él (`null`) el aviso se ve siempre.
  final String? colportorId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloNotas(titulo: titulo),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: AvisoPrivacidadPersona(colportorId: colportorId, texto: TextosNotas.privacidad),
        ),
      ],
    );
  }
}

/// Una nota de la lista (32E·01). Activa: se toca entera para abrir sus opciones (el «⋯» es solo la
/// pista visual). Borrada (32E·05): se ve atenuada y tiene «Restaurar». De solo lectura: se ve igual
/// que la activa, pero no se toca.
///
/// El texto se muestra **entero**, sin recortar, y no se puede seleccionar ni compartir: la HU no
/// quiere «Llamar» ni «Compartir» para el contenido de una nota.
class TarjetaNota extends StatelessWidget {
  const TarjetaNota.activa({
    super.key,
    required this.nota,
    required this.ahora,
    required VoidCallback this.alAbrirOpciones,
    this.conLapiz = false,
    this.margen = margenDeLaPantalla,
  }) : alRestaurar = null,
       atenuada = false;

  const TarjetaNota.borrada({
    super.key,
    required this.nota,
    required this.ahora,
    required this.alRestaurar,
    this.conLapiz = false,
    this.margen = margenDeLaPantalla,
  }) : alAbrirOpciones = null,
       atenuada = true;

  const TarjetaNota.soloLectura({
    super.key,
    required this.nota,
    required this.ahora,
    this.conLapiz = false,
    this.margen = margenDeLaPantalla,
  }) : alAbrirOpciones = null,
       alRestaurar = null,
       atenuada = false;

  final NotaDeTexto nota;
  final DateTime ahora;
  final VoidCallback? alAbrirOpciones;

  /// Con el lápiz «✎» a la izquierda, como las notas del lugar de la hoja (vista 39, C·05).
  final bool conLapiz;

  /// El aire alrededor de la tarjeta: el de una pantalla entera, o el de la hoja (que ya trae el suyo).
  final EdgeInsets margen;

  /// El aire de las tarjetas en una pantalla entera (20 a los lados, 4 arriba y abajo).
  static const margenDeLaPantalla = EdgeInsets.fromLTRB(20, 4, 20, 4);

  /// En una nota borrada: lo que hace «Restaurar». `null` la deja sin el botón (solo lectura).
  final VoidCallback? alRestaurar;

  /// Se dibuja apagada (las borradas).
  final bool atenuada;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>();
    final gris = colores?.gris ?? ColoresAlta.gris;
    final fecha = FormatoNotas.fecha(nota, ahora);
    final lector = '${FormatoNotas.fechaParaLector(nota, ahora)}. ${nota.texto}';
    // Una nota borrada con «Restaurar» lleva el botón dentro de la tarjeta, a la derecha (canvas 32E·05):
    // el lector dice la nota por un lado y el botón por el otro.
    final conRestaurar = alAbrirOpciones == null && alRestaurar != null;
    // Con el texto grande el botón no entra al lado de las notas: va dentro de la tarjeta, abajo a la
    // derecha.
    final restaurarAbajo = conRestaurar && textoGrande(context);

    final botonRestaurar = !conRestaurar
        ? null
        : Semantics(
            container: true,
            button: true,
            excludeSemantics: true,
            label: TextosNotas.restaurarLaNota(FormatoNotas.fechaParaLector(nota, ahora)),
            onTap: alRestaurar,
            child: TextButton(
              onPressed: alRestaurar,
              style: TextButton.styleFrom(
                foregroundColor: ColoresAlta.azul,
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosNotas.restaurar),
            ),
          );

    final textos = Padding(
      padding: const EdgeInsets.only(top: 2, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fecha,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 10,
              letterSpacing: 1.4,
              color: gris,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nota.texto,
            style: TextStyle(fontSize: 15, height: 1.4, color: atenuada ? gris : ColoresAlta.tinta),
          ),
        ],
      ),
    );

    final contenido = Container(
      constraints: BoxConstraints(minHeight: conLapiz ? 56 : 60),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: atenuada ? ColoresAlta.grisFondo.withValues(alpha: .4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colores?.borde ?? ColoresAlta.grisFondo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conLapiz) ...[const _LapizDeLaNota(), const SizedBox(width: 12)],
          Expanded(
            child: !conRestaurar
                ? textos
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        container: true,
                        excludeSemantics: true,
                        label: lector,
                        child: textos,
                      ),
                      if (restaurarAbajo)
                        Align(alignment: Alignment.centerRight, child: botonRestaurar),
                    ],
                  ),
          ),
          if (conRestaurar && !restaurarAbajo) ?botonRestaurar,
          if (alAbrirOpciones != null)
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: 36,
                child: Center(child: Icon(Icons.more_horiz, color: gris)),
              ),
            ),
        ],
      ),
    );

    if (alAbrirOpciones == null) {
      return Padding(
        padding: margen,
        child: conRestaurar
            ? contenido
            : Semantics(container: true, excludeSemantics: true, label: lector, child: contenido),
      );
    }

    return Padding(
      padding: margen,
      child: Semantics(
        container: true,
        button: true,
        excludeSemantics: true,
        label: lector,
        onTapHint: TextosNotas.opcionesDeLaNota.toLowerCase(),
        onTap: alAbrirOpciones,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: alAbrirOpciones,
          child: contenido,
        ),
      ),
    );
  }
}

/// El lápiz de la nota del lugar: un cuadrado de 36 con el fondo `#F2F6FB` y radio 10 (canvas 39, C·05).
class _LapizDeLaNota extends StatelessWidget {
  const _LapizDeLaNota();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6FB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('✎', style: TextStyle(fontSize: 14, color: ColoresAlta.tinta, height: 1)),
      ),
    );
  }
}

/// Lo que se puede hacer con una nota (32E·03).
enum AccionNota { editar, borrar }

/// La hoja de opciones de una nota (32E·03): «Editar», «Borrar» y «Cerrar». Devuelve la
/// [AccionNota] elegida, o `null` si se cerró. Un segundo toque mientras la hoja se cierra no hace
/// nada: si no, el segundo `pop` cerraría la pantalla de abajo.
class HojaOpcionesNota extends StatefulWidget {
  const HojaOpcionesNota({super.key, required this.titulo});

  final String titulo;

  static Future<AccionNota?> mostrar(BuildContext context, {required String titulo}) =>
      showModalBottomSheet<AccionNota>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HojaOpcionesNota(titulo: titulo),
      );

  @override
  State<HojaOpcionesNota> createState() => _HojaOpcionesNotaState();
}

class _HojaOpcionesNotaState extends State<HojaOpcionesNota> {
  var _cerrando = false;

  void _cerrar([AccionNota? accion]) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(accion);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: ClavesNotas.hojaOpciones,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              header: true,
              child: Text(widget.titulo, style: theme.textTheme.titleMedium),
            ),
          ),
          _OpcionNota(
            clave: ClavesNotas.botonEditar,
            icono: Icons.edit_outlined,
            texto: TextosNotas.editar,
            alTocar: () => _cerrar(AccionNota.editar),
          ),
          const SizedBox(height: 8),
          _OpcionNota(
            clave: ClavesNotas.botonBorrar,
            icono: Icons.close,
            texto: TextosNotas.borrar,
            peligrosa: true,
            alTocar: () => _cerrar(AccionNota.borrar),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _cerrar,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(TextosNotas.cerrar),
          ),
        ],
      ),
    );
  }
}

class _OpcionNota extends StatelessWidget {
  const _OpcionNota({
    required this.clave,
    required this.icono,
    required this.texto,
    required this.alTocar,
    this.peligrosa = false,
  });

  final Key clave;
  final IconData icono;
  final String texto;
  final VoidCallback alTocar;
  final bool peligrosa;

  @override
  Widget build(BuildContext context) {
    final color = peligrosa ? ColoresAlta.rojo : ColoresAlta.tinta;
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: texto,
      onTap: alTocar,
      child: InkWell(
        key: clave,
        borderRadius: BorderRadius.circular(12),
        onTap: alTocar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ColoresAlta.grisBorde),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: peligrosa ? const Color(0xFFFBEDEC) : ColoresAlta.azulFondo,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un aviso de una acción sobre una nota, con una acción opcional («Reintentar»). Reemplaza al que
/// hubiera. Con un lector de pantalla no se cierra solo (WCAG 2.2.1). Recibe el mensajero y el
/// `MediaQueryData` ya leídos: la acción puede terminar cuando la pantalla que la lanzó ya se cerró.
void mostrarAvisoDeNota(
  ScaffoldMessengerState mensajero, {
  required MediaQueryData mediaQuery,
  required String texto,
  String? etiquetaAccion,
  VoidCallback? alAccion,
}) {
  mensajero
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        persist: mediaQuery.accessibleNavigation,
        behavior: SnackBarBehavior.floating,
        backgroundColor: ColoresAvisoDeshacer.fondo,
        content: Text(texto, style: const TextStyle(color: ColoresAvisoDeshacer.texto)),
        action: etiquetaAccion == null || alAccion == null
            ? null
            : SnackBarAction(
                label: etiquetaAccion,
                textColor: ColoresAvisoDeshacer.accion,
                onPressed: alAccion,
              ),
      ),
    );
}

/// Las notas que todavía no llegaron (32B·06 para las notas): tres tarjetas grises.
class CargandoNotas extends StatelessWidget {
  const CargandoNotas({super.key, this.horizontal = 20});

  /// El aire a los lados: 20 en una pantalla entera, 0 en la hoja (que ya trae el suyo).
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: TextosNotas.cargando,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 64,
                margin: EdgeInsets.symmetric(horizontal: horizontal, vertical: 4),
                decoration: BoxDecoration(
                  color: ColoresAlta.grisFondo,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// El estado vacío (32E·06): un ícono, qué pasa y qué hacer.
class VacioNotas extends StatelessWidget {
  const VacioNotas({super.key, required this.titulo, required this.ayuda, this.horizontal = 20});

  final String titulo;
  final String ayuda;

  /// El aire a los lados: 20 en una pantalla entera, 0 en la hoja (que ya trae el suyo).
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 32, horizontal, 12),
      child: Column(
        children: [
          Icon(Icons.edit_note, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(titulo, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(ayuda, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
