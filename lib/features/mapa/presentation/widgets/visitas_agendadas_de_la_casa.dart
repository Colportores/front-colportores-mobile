import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/item_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/presentation/formato_agenda.dart';
import '../../../agenda/presentation/providers/consulta_agenda_providers.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/estado_casa.dart';
import '../providers/cobranza_recien_agendada_providers.dart';
import 'estados_hoja_casa.dart';
import 'piezas_alta.dart' show ColoresAlta;
import 'piezas_lista_ubicaciones.dart' show InsigniaEstadoCasa;

/// Las claves de «Visitas agendadas», para los tests y para quien las monta.
abstract final class ClavesVisitasAgendadas {
  static const seccion = Key('visitas_agendadas');
  static const rotulo = Key('visitas_agendadas_rotulo');
  static Key fila(String agendaId) => Key('visita_agendada_$agendaId');

  /// La tarjeta de la cobranza recién agendada (R·08) y su «Cambiar».
  static const tarjetaCobranza = Key('visitas_agendadas_tarjeta_cobranza');
  static const cambiar = Key('visitas_agendadas_cambiar');
}

/// «VISITAS AGENDADAS» de la hoja de la casa (vista 23, 23B·10 «En el mapa: tocar la casa»): las
/// visitas `PROGRAMADA` de la casa —la entrevista del jueves, la cobranza del sábado—, de la más
/// temprana a la más tardía, no solo la próxima. Es la misma lista de la Agenda filtrada por esa casa;
/// tocar una abre su detalle (23C·01).
///
/// - **Venta recién guardada** (R·08): la cobranza que se agendó al guardarla se dibuja como una
///   tarjeta, «Cobranza · Pedro / Agendada al registrar la venta» con «Cambiar», que abre el mismo
///   detalle (23C·01) que la fila; no se repite en la lista. Es solo mientras esta hoja sigue
///   abierta: si la cita se cambia de día, se cancela o se cumple, la tarjeta sigue a la lista.
/// - Sin visitas agendadas —o mientras lee— no ocupa lugar. Con la casa o el depto dados de baja la
///   agenda está oculta (HU-VIS-002, «Agenda baja»), así que tampoco se dibuja.
/// - Si no se puede leer, esta lista no dibuja nada: el aviso «No pudimos leer tu agenda.» con
///   «Reintentar» es [AvisoErrorVisitasAgendadas], que la hoja pone arriba de la persona para que se
///   vea sin desplazar (decisión del 29/10, QA #491 P1).
/// - El detalle se abre de a uno ([abrirDetalleDeAgendaProvider]): un doble toque, o dos filas
///   seguidas, abren una sola vez; si falla, avisa y las filas vuelven a poder tocarse. **Sin destino**
///   las filas no se tocan y no llevan la flecha «›».
class VisitasAgendadasDeLaCasa extends ConsumerStatefulWidget {
  const VisitasAgendadasDeLaCasa({
    super.key,
    required this.colportorId,
    required this.ubicacionId,
    required this.ahora,
  });

  final String colportorId;
  final String ubicacionId;
  final DateTime ahora;

  @override
  ConsumerState<VisitasAgendadasDeLaCasa> createState() => _VisitasAgendadasDeLaCasaState();
}

class _VisitasAgendadasDeLaCasaState extends ConsumerState<VisitasAgendadasDeLaCasa> {
  /// Hay un detalle abierto: la guarda es un campo y no solo estado de la UI para que corte el segundo
  /// toque aunque llegue antes de volver a dibujar.
  bool _abriendo = false;

  /// La cobranza que se agendó al guardar la venta de esta casa (R·08), mientras la hoja sigue abierta.
  CobranzaRecienAgendada? _recien;
  var _montada = false;

  @override
  void initState() {
    super.initState();
    // La hoja la toma una vez: así la tarjeta no reaparece al volver a abrir la casa otro día.
    ref.listenManual(cobranzaRecienAgendadaProvider, (_, cobranza) {
      if (cobranza == null || cobranza.ubicacionId != widget.ubicacionId) return;
      if (_montada) {
        setState(() => _recien = cobranza);
      } else {
        _recien = cobranza;
      }
      unawaited(
        Future.microtask(() {
          if (mounted) ref.read(cobranzaRecienAgendadaProvider.notifier).consumir();
        }),
      );
    }, fireImmediately: true);
    _montada = true;
  }

  Future<void> _abrir(FutureOr<Object?> Function(String) destino, String agendaId) async {
    if (_abriendo) return;
    _abriendo = true;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      await destino(agendaId);
    } on Object {
      // El detalle del error puede llevar datos de la visita: se avisa y no se loguea.
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAgenda.noPudimosAbrir)));
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clave = (colportorId: widget.colportorId, ubicacionId: widget.ubicacionId);
    final leida = ref.watch(visitasAgendadasDeLaCasaProvider(clave));
    final detalle = ref.watch(abrirDetalleDeAgendaProvider);

    // Con un error (también el que llega después de los primeros datos) la lista no se dibuja: el
    // aviso va aparte, arriba en la hoja.
    final todas = leida.hasError ? null : leida.value;
    if (todas == null || todas.isEmpty) return const SizedBox.shrink();
    final recien = _recien;
    final tarjeta = recien == null
        ? null
        : todas.where((v) => v.agenda.id == recien.agendaId).firstOrNull;
    final visitas = tarjeta == null
        ? todas
        : todas.where((v) => v.agenda.id != tarjeta.agenda.id).toList();
    return Column(
      key: ClavesVisitasAgendadas.seccion,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (tarjeta != null)
          TarjetaCobranzaAgendada(
            key: ClavesVisitasAgendadas.tarjetaCobranza,
            item: tarjeta,
            persona: recien!.persona,
            ahora: widget.ahora,
            alCambiar: detalle == null ? null : () => unawaited(_abrir(detalle, tarjeta.agenda.id)),
          ),
        if (visitas.isNotEmpty)
          Semantics(
            header: true,
            child: const Text(
              TextosAgenda.visitasAgendadas,
              key: ClavesVisitasAgendadas.rotulo,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                color: ColoresAgenda.gris,
              ),
            ),
          ),
        for (final visita in visitas)
          FilaVisitaAgendada(
            key: ClavesVisitasAgendadas.fila(visita.agenda.id),
            item: visita,
            ahora: widget.ahora,
            alTocar: detalle == null ? null : () => unawaited(_abrir(detalle, visita.agenda.id)),
          ),
      ],
    );
  }
}

/// La cobranza agendada al guardar la venta (vista 39, R·08): cuándo («SÁB 26/10 · 12:30»), «Cobranza ·
/// Pedro», «Agendada al registrar la venta» y «Cambiar», que abre el detalle de la cita. Sin [alCambiar]
/// no se toca y no lleva «Cambiar».
class TarjetaCobranzaAgendada extends StatelessWidget {
  const TarjetaCobranzaAgendada({
    super.key,
    required this.item,
    required this.persona,
    required this.ahora,
    this.alCambiar,
  });

  final ItemAgenda item;
  final String persona;
  final DateTime ahora;
  final VoidCallback? alCambiar;

  @override
  Widget build(BuildContext context) {
    final cuando = FormatoAgenda.cuandoCorto(item.agenda.fechaProgramada, ahora);
    final titulo = TextosAgenda.cobranzaDe(persona);
    // Con el texto muy grande «Cambiar» no entra al lado: baja debajo del texto de la tarjeta.
    final apilado = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    const cambiar = Text(
      TextosAgenda.cambiarLaCita,
      key: ClavesVisitasAgendadas.cambiar,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: ColoresAgenda.azul,
      ),
    );
    final contenido = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ColoresAgenda.azul,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            r'$',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cuando,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  color: ColoresAgenda.navy,
                ),
              ),
              Text(
                titulo,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.tinta,
                ),
              ),
              const Text(
                TextosAgenda.agendadaAlRegistrarLaVenta,
                style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: ColoresAgenda.tinta),
              ),
              if (alCambiar != null && apilado) ...[const SizedBox(height: 6), cambiar],
            ],
          ),
        ),
        if (alCambiar != null && !apilado) ...[const SizedBox(width: 8), cambiar],
      ],
    );
    return Semantics(
      container: true,
      button: alCambiar != null,
      label: [
        titulo,
        cuando,
        TextosAgenda.agendadaAlRegistrarLaVenta,
        if (alCambiar != null) TextosAgenda.cambiarLaCita,
      ].join('. '),
      onTap: alCambiar,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E7EE), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Material(
            color: Colors.transparent,
            child: alCambiar == null
                ? Padding(padding: const EdgeInsets.all(12), child: contenido)
                : InkWell(
                    onTap: alCambiar,
                    child: Padding(padding: const EdgeInsets.all(12), child: contenido),
                  ),
          ),
        ),
      ),
    );
  }
}

/// El aviso «No pudimos leer tu agenda.» con «Reintentar» de «Visitas agendadas»: va arriba de la
/// persona, bajo el subtítulo, para que se vea sin desplazar aunque la hoja esté a un tercio de la
/// pantalla (con «Reintentar» al lado del texto, no debajo). Se anuncia una sola vez como mensaje de
/// estado, región viva (WCAG 4.1.3). Sin error —o mientras lee—
/// no ocupa lugar. Un error que llega después de los primeros datos también se dice: la lista ya no se
/// sabe al día.
class AvisoErrorVisitasAgendadas extends ConsumerWidget {
  const AvisoErrorVisitasAgendadas({
    super.key,
    required this.colportorId,
    required this.ubicacionId,
  });

  final String colportorId;
  final String ubicacionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clave = (colportorId: colportorId, ubicacionId: ubicacionId);
    if (!ref.watch(visitasAgendadasDeLaCasaProvider(clave)).hasError) {
      return const SizedBox.shrink();
    }
    return AvisoHojaCasa.errorAlLeerAgendas(
      alReintentar: () => ref.invalidate(visitasAgendadasDeLaCasaProvider(clave)),
    );
  }
}

/// Una visita agendada de la casa (23B·10): cuándo («JUE 24/10 · 14:30»), el tipo («Entrevista»,
/// «Cobranza») y con quién («María Fernández · en Av. Italia 2810»). Alto mínimo 64; sin [alTocar] no
/// se toca y no lleva «›».
class FilaVisitaAgendada extends StatelessWidget {
  const FilaVisitaAgendada({super.key, required this.item, required this.ahora, this.alTocar});

  final ItemAgenda item;
  final DateTime ahora;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final vencida = item.estaVencida(ahora);
    final cuando = FormatoAgenda.cuandoCorto(item.agenda.fechaProgramada, ahora);
    final tipo = FormatoAgenda.tipo(item.agenda.tipo);
    final subtitulo = FormatoAgenda.subtituloDeVisitaDeLaCasa(item);
    final contenido = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InsigniaEstadoCasa(
          estado: item.agenda.tipo == TipoAgenda.entrevista
              ? EstadoCasa.entrevistaAgendada
              : EstadoCasa.cobranzaPendiente,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                cuando,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  color: ColoresAgenda.navy,
                ),
              ),
              Text(
                tipo,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.tinta,
                ),
              ),
              if (subtitulo != null)
                Text(
                  subtitulo,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: ColoresAgenda.tinta,
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
        ),
        if (alTocar != null) ...[
          const SizedBox(width: 8),
          const Text('›', style: TextStyle(color: Color(0xFF90A0B7), fontSize: 18)),
        ],
      ],
    );
    return Semantics(
      container: true,
      button: alTocar != null,
      label: [cuando, tipo, ?subtitulo, if (vencida) TextosAgenda.pasoLaHora].join('. '),
      onTap: alTocar,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: vencida ? ColoresAlta.ambarBorde : const Color(0xFFE3E7EE),
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Material(
            color: Colors.transparent,
            child: alTocar == null
                ? Padding(padding: const EdgeInsets.all(12), child: contenido)
                : InkWell(
                    onTap: alTocar,
                    child: Padding(padding: const EdgeInsets.all(12), child: contenido),
                  ),
          ),
        ),
      ),
    );
  }
}
