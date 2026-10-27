import 'package:flutter/material.dart';

import '../../../mapa/domain/entities/estado_casa.dart';
import '../../../mapa/presentation/widgets/piezas_alta.dart' show ColoresAlta, EnlaceAlta;
import '../../../mapa/presentation/widgets/piezas_lista_ubicaciones.dart' show InsigniaEstadoCasa;
import '../../domain/entities/estado_agenda.dart';
import '../../domain/entities/item_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../formato_agenda.dart';

/// Los colores de la agenda (vista 23B) que el tema no cubre.
abstract final class ColoresAgenda {
  static const navy = Color(0xFF002856);
  static const azul = Color(0xFF13407A);
  static const azulFondo = Color(0xFFE6EEF8);
  static const ambarFondo = Color(0xFFFBF1DA);
  static const ambarTinta = Color(0xFF6E5212);
  static const rojo = Color(0xFFA8312A);
  static const tinta = Color(0xFF2A3A52);
  static const gris = Color(0xFF5B6B82);
  static const grisFondo = Color(0xFFF3F1EA);
  static const esqueleto = Color(0xFFEDEBE4);
  static const bordeChip = Color(0xFFCFD6E1);
}

/// El encabezado de la pestaña: «AGENDA», «Agenda» y «Hoy y los próximos 7 días».
class CabeceraAgenda extends StatelessWidget {
  const CabeceraAgenda({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Text(
              TextosAgenda.eyebrow,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 2,
                color: ColoresAgenda.navy,
              ),
            ),
          ),
          Semantics(
            header: true,
            child: const Text(
              TextosAgenda.titulo,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Text(
            TextosAgenda.subtitulo,
            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: ColoresAgenda.gris),
          ),
        ],
      ),
    );
  }
}

/// `true` desde el 130 % (el «Grande» de Android): la columna de 44 dp de la hora ya no alcanza
/// para «16:00» ni para el día y la hora, y la fila los pasa arriba del título.
bool _textoGrandeAgenda(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) >= 13;

/// Un chip de filtro de la agenda: alto mínimo 38 (área táctil de 48), borde de 1,5 y, elegido, navy
/// con texto blanco.
class ChipAgenda extends StatelessWidget {
  const ChipAgenda({
    super.key,
    required this.texto,
    required this.elegido,
    required this.alPresionar,
    this.etiqueta,
  });

  final String texto;
  final bool elegido;
  final VoidCallback alPresionar;

  /// Lo que dice el lector de pantalla, si no es el texto.
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      label: etiqueta ?? texto,
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alPresionar,
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: elegido ? ColoresAgenda.navy : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: elegido ? ColoresAgenda.navy : ColoresAgenda.bordeChip,
                    width: 1.5,
                  ),
                ),
                // `widthFactor: 1`: el chip mide lo que su texto; un `alignment` en el `Container`
                // lo estiraría al ancho del `Wrap` y cada chip quedaría en su propia fila.
                child: Align(
                  widthFactor: 1,
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: elegido ? Colors.white : ColoresAgenda.tinta,
                    ),
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

/// El rótulo de un día («HOY · MIÉRCOLES 23 (3)») y, a la derecha, la acción de agendar si hay a
/// dónde llevarla.
class RotuloDeDia extends StatelessWidget {
  const RotuloDeDia({super.key, required this.texto, this.alAgendar});

  final String texto;

  /// `null`: no se muestra «+ Agendar».
  final VoidCallback? alAgendar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(
              texto,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresAgenda.gris,
              ),
            ),
          ),
          if (alAgendar != null)
            TextButton(
              key: const Key('agenda_agendar'),
              onPressed: alAgendar,
              style: TextButton.styleFrom(
                foregroundColor: ColoresAgenda.azul,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosAgenda.agendar),
            ),
        ],
      ),
    );
  }
}

/// Una agenda: hora, glifo del tipo, persona, dirección y etiqueta (canvas 23B·01). Cuatro formas:
/// - **programada**: la «›» de «se abre» si hay a dónde ir ([alTocar]);
/// - **vencida** (23B·02): borde ámbar, «Pasó la hora · registrá qué pasó» y «Registrar» en lugar de
///   la «›» ([alRegistrar]);
/// - **cancelada** (23B·05): tachada y atenuada, con «Cancelada el 22/10»;
/// - **cumplida / no cumplida**: igual que la cancelada, con su etiqueta.
class FilaAgenda extends StatelessWidget {
  const FilaAgenda({
    super.key,
    required this.item,
    required this.ahora,
    this.alTocar,
    this.alRegistrar,
    this.registrarHabilitado = true,
    this.conFecha = false,
  });

  final ItemAgenda item;
  final DateTime ahora;

  /// La fila lleva el día además de la hora («26/10 · 09:30»): las del grupo «ATRASADAS» son de
  /// días distintos y la hora sola no las distingue.
  final bool conFecha;

  /// `null`: la fila no se toca y no lleva «›» (todavía no hay detalle a dónde ir).
  final VoidCallback? alTocar;

  /// `null`: la vencida no ofrece «Registrar».
  final VoidCallback? alRegistrar;

  /// `false`: «Registrar» se ve pero apagado (hay otro registro abierto y no se pisan).
  final bool registrarHabilitado;

  @override
  Widget build(BuildContext context) {
    final vencida = item.estaVencida(ahora);
    final cerrada = item.agenda.estado != EstadoAgenda.programada;
    final cancelada = item.agenda.estado == EstadoAgenda.cancelada;
    final apilada = _textoGrandeAgenda(context);
    final subtitulo = FormatoAgenda.subtitulo(item);
    final cierre = FormatoAgenda.cierre(item);
    final conRegistrar = vencida && alRegistrar != null;
    final conFlecha = !conRegistrar && alTocar != null;

    final horaTexto = FormatoAgenda.hora(item.agenda.fechaProgramada);
    final fechaTexto = FormatoAgenda.diaMes(item.agenda.fechaProgramada);
    final hora = Text(
      // Apilada hay ancho de sobra: en una línea. Si no, el día arriba de la hora en los 44 px.
      !conFecha ? horaTexto : (apilada ? '$fechaTexto · $horaTexto' : '$fechaTexto\n$horaTexto'),
      style: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: 11,
        color: cerrada ? ColoresAgenda.gris : ColoresAgenda.tinta,
      ),
    );
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (apilada) hora,
        Opacity(
          opacity: cancelada ? .7 : 1,
          child: Text(
            FormatoAgenda.titulo(item),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              decoration: cancelada ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (subtitulo != null)
          Text(
            subtitulo,
            style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: ColoresAgenda.tinta),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Etiqueta(item: item),
            if (cierre != null)
              Text(
                cierre,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: ColoresAgenda.gris,
                ),
              ),
            if (vencida)
              const Text(
                TextosAgenda.pasoLaHora,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.rojo,
                ),
              ),
          ],
        ),
      ],
    );

    final insignia = Opacity(
      opacity: cancelada ? .7 : 1,
      child: InsigniaEstadoCasa(
        estado: item.agenda.tipo == TipoAgenda.entrevista
            ? EstadoCasa.entrevistaAgendada
            : EstadoCasa.cobranzaPendiente,
      ),
    );

    final registrar = conRegistrar
        ? TextButton(
            key: Key('agenda_registrar_${item.agenda.id}'),
            onPressed: registrarHabilitado ? alRegistrar : null,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAgenda.azul,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosAgenda.registrar),
          )
        : null;

    final izquierda = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!apilada) ...[SizedBox(width: 44, child: hora), const SizedBox(width: 8)],
          insignia,
          const SizedBox(width: 12),
          Expanded(child: contenido),
          if (conFlecha) ...[
            const SizedBox(width: 8),
            const Text('›', style: TextStyle(color: Color(0xFF90A0B7), fontSize: 18)),
          ],
        ],
      ),
    );
    // La parte de la izquierda se lee de una sola vez con la etiqueta de la fila: sin semántica propia.
    final tocable = ExcludeSemantics(
      child: alTocar == null ? izquierda : InkWell(onTap: alTocar, child: izquierda),
    );
    final Widget interior;
    if (registrar == null) {
      interior = tocable;
    } else if (apilada) {
      interior = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tocable,
          Align(
            alignment: Alignment.centerRight,
            child: Padding(padding: const EdgeInsets.only(right: 6, bottom: 4), child: registrar),
          ),
        ],
      );
    } else {
      interior = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: tocable),
          Padding(padding: const EdgeInsets.only(right: 6), child: registrar),
        ],
      );
    }

    final tarjeta = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        color: cerrada ? ColoresAgenda.grisFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: vencida ? ColoresAlta.ambarBorde : const Color(0xFFE3E7EE),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.5),
        child: Material(color: Colors.transparent, child: interior),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        container: true,
        button: alTocar != null,
        label: FormatoAgenda.etiquetaDeFila(item, vencida: vencida, conFecha: conFecha),
        onTap: alTocar,
        child: tarjeta,
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.item});

  final ItemAgenda item;

  @override
  Widget build(BuildContext context) {
    final (Color fondo, Color tinta) = switch (item.agenda.estado) {
      EstadoAgenda.programada when item.agenda.tipo == TipoAgenda.entrevista => (
        ColoresAgenda.ambarFondo,
        ColoresAgenda.ambarTinta,
      ),
      EstadoAgenda.programada => (ColoresAgenda.azulFondo, ColoresAgenda.azul),
      _ => (Colors.white, ColoresAgenda.gris),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(99),
        border: item.agenda.estado == EstadoAgenda.programada
            ? null
            : Border.all(color: ColoresAgenda.bordeChip),
      ),
      child: Text(
        FormatoAgenda.etiqueta(item),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tinta,
        ),
      ),
    );
  }
}

/// La carga (23B·06): bloques grises donde irán los rótulos y las filas.
class EsqueletoAgenda extends StatelessWidget {
  const EsqueletoAgenda({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto, {double? ancho}) => Container(
      height: alto,
      width: ancho,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosAgenda.cargando,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: bloque(22, ancho: 140)),
              const SizedBox(height: 10),
              bloque(64),
              const SizedBox(height: 8),
              bloque(64),
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft, child: bloque(22, ancho: 120)),
              const SizedBox(height: 10),
              bloque(64),
            ],
          ),
        ),
      ),
    );
  }
}

/// La pantalla sin filas (23B·07 y 23B·08): un círculo con glifo, un título, un texto y una acción.
class HeroAgenda extends StatelessWidget {
  const HeroAgenda({
    super.key,
    required this.glifo,
    required this.titulo,
    this.textoAccion,
    this.alAccion,
    this.cuerpo,
  });

  final String glifo;
  final String titulo;
  final String? cuerpo;

  /// El texto del botón; sin [alAccion] no se muestra.
  final String? textoAccion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: ColoresAgenda.azulFondo,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  glifo,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 30, color: ColoresAgenda.navy),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (cuerpo != null) ...[
              const SizedBox(height: 8),
              Text(
                cuerpo!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: ColoresAgenda.tinta,
                  height: 1.4,
                ),
              ),
            ],
            if (alAccion != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: alAccion,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: ColoresAgenda.navy,
                  side: const BorderSide(color: ColoresAgenda.navy, width: 1.5),
                  textStyle: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(textoAccion ?? '', textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El error de lectura (23B·09): «No pudimos leer tu agenda.» con «Reintentar». Se anuncia al aparecer.
class BannerErrorAgenda extends StatelessWidget {
  const BannerErrorAgenda({super.key, required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ColoresAgenda.rojo, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: ColoresAgenda.rojo,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '!',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        TextosAgenda.errorLectura,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: EnlaceAlta(texto: TextosAgenda.reintentar, alPresionar: alReintentar),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
