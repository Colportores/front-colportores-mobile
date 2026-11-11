import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/item_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/armador_agendados.dart';
import '../../../agenda/presentation/formato_agenda.dart';
import '../../../agenda/presentation/providers/consulta_agenda_providers.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart';
import '../../../cobranzas/presentation/providers/cobranzas_providers.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_agendados.dart';
import '../providers/ubicacion_colportor_provider.dart';
import 'piezas_lista_ubicaciones.dart' show InsigniaEstadoCasa;

/// Las claves de la hoja «Agendados» para los tests.
abstract final class ClavesAgendados {
  static const pestana = Key('mapa_pestana_agendados');
  static const lista = Key('mapa_agendados_lista');
  static const cargando = Key('mapa_agendados_cargando');
  static const error = Key('mapa_agendados_error');
  static const vacia = Key('mapa_agendados_vacia');
  static const sinResultados = Key('mapa_agendados_sin_resultados');
  static const atrasados = Key('mapa_agendados_atrasados');
  static Key chip(TipoAgenda? tipo) => Key('mapa_agendados_chip_${tipo?.name ?? 'todos'}');
  static Key dia(DateTime dia) => Key('mapa_agendados_dia_${dia.millisecondsSinceEpoch}');
  static Key fila(String agendaId) => Key('mapa_agendados_fila_$agendaId');
}

/// Lo que se ve debajo de las pestañas con «Agendados» elegida (vista 06, 06C·03): los chips de tipo
/// con su cuenta y, debajo, las visitas agrupadas por día con las atrasadas arriba. Cada fila dice
/// cuándo, a dónde, qué (con la cuota y lo que falta cobrar) y a cuánto está.
///
/// La distancia se mide desde donde estaba la colportora **al abrir la hoja** (decisión de Cristian,
/// 27/10, «Hoja Agend.»): no cambia mientras camina, para que la lista no salte; se vuelve a medir la
/// próxima vez que la abre. Si no había GPS, toma la primera lectura que llegue.
///
/// Los estados son los de la pestaña Agenda (#406): cargando, vacía, filtro sin resultados y error al
/// leer, dentro de la hoja.
class ContenidoAgendados extends ConsumerStatefulWidget {
  const ContenidoAgendados({
    super.key,
    required this.agendados,
    required this.tipo,
    required this.ahora,
    required this.alElegirTipo,
    required this.alReintentar,
  });

  /// La hoja armada (`ArmadorAgendados`), cargando o el error de la lectura.
  final AsyncValue<VistaAgendados> agendados;

  /// El chip elegido (`null` = «Todos»).
  final TipoAgenda? tipo;
  final DateTime ahora;
  final ValueChanged<TipoAgenda?> alElegirTipo;
  final VoidCallback alReintentar;

  @override
  ConsumerState<ContenidoAgendados> createState() => _ContenidoAgendadosState();
}

class _ContenidoAgendadosState extends ConsumerState<ContenidoAgendados> {
  /// Desde dónde se miden las distancias: el GPS al abrir la hoja.
  Coordenadas? _origen;

  /// Un solo destino abierto a la vez: un segundo toque (o dos filas seguidas) no abre otro encima.
  var _abriendo = false;

  @override
  void initState() {
    super.initState();
    _origen = ref.read(ubicacionColportorProvider).lectura?.coordenadas;
    if (_origen == null) {
      ref.listenManual(ubicacionColportorProvider.select((g) => g.lectura?.coordenadas), (
        _,
        nueva,
      ) {
        if (_origen == null && nueva != null && mounted) setState(() => _origen = nueva);
      });
    }
  }

  /// Corre [accion] si no hay otra en curso. Pase lo que pase —incluso si el destino falla— la hoja
  /// vuelve a quedar libre y lo dice, para que nada quede trabado sin explicación.
  Future<void> _sola(FutureOr<Object?> Function() accion) async {
    if (_abriendo) return;
    _abriendo = true;
    final mensajero = ScaffoldMessenger.maybeOf(context);
    try {
      await accion();
    } on Object {
      mensajero?.showSnackBar(const SnackBar(content: Text(TextosAgenda.noPudimosAbrir)));
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final agendados = widget.agendados;
    if (agendados.hasError) {
      return SingleChildScrollView(
        key: ClavesAgendados.error,
        child: BannerErrorAgenda(alReintentar: widget.alReintentar),
      );
    }
    final vista = agendados.value;
    if (vista == null) {
      return const SingleChildScrollView(key: ClavesAgendados.cargando, child: EsqueletoAgenda());
    }
    final agendar = ref.watch(agendarDesdeLaAgendaProvider);
    final detalle = ref.watch(abrirDetalleDeAgendaProvider);
    if (vista.cuentas.todas == 0) {
      return SingleChildScrollView(
        key: ClavesAgendados.vacia,
        child: HeroAgenda(
          glifo: '▦',
          titulo: TextosAgenda.vaciaTitulo,
          cuerpo: TextosAgenda.vaciaCuerpo,
          textoAccion: TextosAgenda.agendar,
          alAccion: agendar == null ? null : () => unawaited(_sola(agendar)),
        ),
      );
    }

    final lista = vista.vista;
    final entradas = <Object>[
      _Chips(cuentas: vista.cuentas, elegido: widget.tipo, alElegir: widget.alElegirTipo),
      if (lista.estaVacia)
        HeroAgenda(
          key: ClavesAgendados.sinResultados,
          glifo: '⌕',
          titulo: TextosAgenda.sinResultadosTitulo,
          textoAccion: TextosAgenda.limpiarFiltros,
          alAccion: () => widget.alElegirTipo(null),
        )
      else ...[
        if (lista.atrasadas.isNotEmpty) ...[
          _Rotulo(
            key: ClavesAgendados.atrasados,
            texto: TextosAgendados.atrasados,
            cuenta: lista.atrasadas.length,
            atrasados: true,
          ),
          for (final item in lista.atrasadas) (item: item, atrasada: true),
        ],
        for (final dia in lista.dias) ...[
          _Rotulo(
            key: ClavesAgendados.dia(dia.dia),
            texto: FormatoAgendados.rotuloDelDia(dia),
            cuenta: dia.cantidad,
          ),
          for (final item in dia.items) (item: item, atrasada: false),
        ],
      ],
    ];
    final origen = _origen;
    return ListView.builder(
      key: ClavesAgendados.lista,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entradas.length,
      itemBuilder: (context, i) {
        final entrada = entradas[i];
        if (entrada is Widget) return entrada;
        final (:item, :atrasada) = entrada as ({ItemAgenda item, bool atrasada});
        final coordenadas = item.lugar?.coordenadas;
        return FilaAgendado(
          key: ClavesAgendados.fila(item.agenda.id),
          item: item,
          atrasada: atrasada,
          ahora: widget.ahora,
          metros: origen == null || coordenadas == null
              ? null
              : origen.distanciaMetrosA(coordenadas),
          alTocar: detalle == null ? null : () => unawaited(_sola(() => detalle(item.agenda.id))),
        );
      },
    );
  }
}

/// Los colores de la hoja «Agendados» (canvas 06C·03).
abstract final class _Colores {
  static const navy = Color(0xFF002856);
  static const rojo = Color(0xFFA8312A);
  static const tinta = Color(0xFF2A3A52);
  static const oscuro = Color(0xFF0E1A2B);
  static const gris = Color(0xFF5B6B82);
  static const cuentaElegida = Color(0xFFC9D6EA);
  static const bordeChip = Color(0xFFCFD6E1);
  static const separador = Color(0xFFEDEBE4);
}

/// «Todos 6», «$ Cobranzas 3», «◷ Entrevistas 2» y «⇢ Entregas 1». Bajan de renglón si no entran (con
/// el texto grande).
class _Chips extends StatelessWidget {
  const _Chips({required this.cuentas, required this.elegido, required this.alElegir});

  final CuentasAgendados cuentas;
  final TipoAgenda? elegido;
  final ValueChanged<TipoAgenda?> alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: TextosAgendados.filtrarPorTipo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tipo in const [
              null,
              TipoAgenda.cobranza,
              TipoAgenda.entrevista,
              TipoAgenda.entrega,
            ])
              _Chip(
                key: ClavesAgendados.chip(tipo),
                tipo: tipo,
                cuenta: tipo == null ? cuentas.todas : cuentas.de(tipo),
                elegido: tipo == elegido,
                alPresionar: () => alElegir(tipo),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.tipo,
    required this.cuenta,
    required this.elegido,
    required this.alPresionar,
  });

  final TipoAgenda? tipo;
  final int cuenta;
  final bool elegido;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final tipo = this.tipo;
    return Semantics(
      container: true,
      button: true,
      selected: elegido,
      label: FormatoAgendados.etiquetaChip(tipo, cuenta),
      onTap: alPresionar,
      excludeSemantics: true,
      child: InkWell(
        onTap: alPresionar,
        borderRadius: BorderRadius.circular(20),
        // 48 dp de objetivo táctil; el chip dibujado es más bajo (canvas).
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: elegido ? _Colores.navy : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: elegido ? _Colores.navy : _Colores.bordeChip, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  if (tipo != null)
                    InsigniaEstadoCasa(estado: FormatoAgendados.estadoDe(tipo), tamano: 18),
                  Flexible(
                    child: Text(
                      FormatoAgendados.chip(tipo),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: elegido ? Colors.white : _Colores.navy,
                      ),
                    ),
                  ),
                  Text(
                    '$cuenta',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11.5,
                      color: elegido ? _Colores.cuentaElegida : _Colores.gris,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «ATRASADOS 1», «HOY 3», «MAÑANA 2», «VIERNES 25 1».
class _Rotulo extends StatelessWidget {
  const _Rotulo({super.key, required this.texto, required this.cuenta, this.atrasados = false});

  final String texto;
  final int cuenta;
  final bool atrasados;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '$texto, $cuenta',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              texto,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
                color: atrasados ? _Colores.rojo : _Colores.tinta,
              ),
            ),
            Text(
              '$cuenta',
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                color: _Colores.gris,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una visita de la hoja «Agendados»: «15:00 · $ · Av. Italia 1234 · Cobranza · 2.ª cuota · $U 1.450 ·
/// 40 m». La cuota, lo que falta cobrar y si la entrega lleva un pago salen del plan de la venta de la
/// visita, que la fila lee y sigue (un cobro la actualiza sola). Mientras no se sabe, dice el tipo
/// solo.
class FilaAgendado extends ConsumerWidget {
  const FilaAgendado({
    super.key,
    required this.item,
    required this.atrasada,
    required this.ahora,
    this.metros,
    this.alTocar,
  });

  final ItemAgenda item;

  /// Es del grupo «ATRASADOS»: lleva el día en vez de la hora y el detalle en rojo.
  final bool atrasada;
  final DateTime ahora;

  /// A cuánto está, desde el GPS al abrir la hoja; `null` sin GPS o sin el punto de la casa.
  final double? metros;

  /// Abre el detalle de la visita (HU-VIS-003); `null` = no se toca.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ventaId = item.agenda.ventaId;
    final leePlan = ventaId != null && item.agenda.tipo != TipoAgenda.entrevista;
    final plan = leePlan ? ref.watch(planDeLaVentaProvider(ventaId)).value : null;
    final cobro = plan == null ? null : CobroDeAgendado.de(item, plan);
    final distancia = FormatoAgendados.distancia(metros);
    final escala = MediaQuery.textScalerOf(context);
    final rojoDetalle = atrasada && item.agenda.tipo == TipoAgenda.cobranza;

    return Semantics(
      container: true,
      button: alTocar != null,
      label: FormatoAgendados.etiquetaDeFila(
        item,
        cobro,
        atrasada: atrasada,
        ahora: ahora,
        metros: metros,
      ),
      onTap: alTocar,
      excludeSemantics: true,
      child: InkWell(
        onTap: alTocar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _Colores.separador)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: escala.scale(44),
                child: Text(
                  FormatoAgendados.cuando(item, atrasada: atrasada, ahora: ahora),
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: atrasada ? _Colores.rojo : _Colores.oscuro,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InsigniaEstadoCasa(estado: FormatoAgendados.estadoDe(item.agenda.tipo), tamano: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      FormatoAgendados.lugar(item),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _Colores.oscuro,
                      ),
                    ),
                    Text(
                      FormatoAgendados.detalle(item, cobro, atrasada: atrasada),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        fontWeight: rojoDetalle ? FontWeight.w600 : FontWeight.w400,
                        color: rojoDetalle ? _Colores.rojo : _Colores.tinta,
                      ),
                    ),
                  ],
                ),
              ),
              if (distancia != null) ...[
                const SizedBox(width: 8),
                Text(
                  distancia,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    color: _Colores.tinta,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
