import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../providers/baja_persona_providers.dart';
import '../textos_baja_persona.dart';
import '../textos_personas.dart';
import 'piezas_alta.dart';

// «Mostrar bajas» de las personas de un espacio (HU-UBI-011, canvas 32D·04 y 32D·05): el interruptor,
// las bajas en gris con la fecha y el saldo si se conoce, y «Reactivar». Lo usan la ficha del depto
// (vista 11·04, `PersonasDelEspacioPage`) y la pestaña «Personas» de la hoja de la casa (vista 39,
// C·02): las dos con las mismas piezas y la misma reactivación.

/// Las claves de «Mostrar bajas».
abstract final class ClavesBajasDePersonas {
  static const mostrar = Key('bajas_personas_mostrar');
  static const error = Key('bajas_personas_error');

  /// La fila de la persona dada de baja [personaId].
  static Key fila(String personaId) => Key('bajas_personas_fila_$personaId');

  /// «Reactivar» de la persona [personaId].
  static Key reactivar(String personaId) => Key('bajas_personas_reactivar_$personaId');
}

/// El estado de «Mostrar bajas» de una pantalla (el interruptor y las reactivaciones en curso) y la
/// reactivación misma. La pantalla dice dónde se ven los avisos ([avisarReactivada] y
/// [avisarFallaAlReactivar]): en la ficha del depto, abajo; en la hoja de la casa, dentro de la hoja
/// (un `SnackBar` quedaría tapado por la hoja modal).
mixin BajasDePersonasDelEspacio<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// «Mostrar bajas» (32D·04): apagado al abrir la pantalla.
  var _mostrarBajas = false;

  /// Las personas que se están reactivando: un segundo toque sobre la misma no la pide dos veces.
  final _reactivando = <String>{};

  /// «Reactivamos a María.» (32D·05).
  void avisarReactivada(String texto);

  /// La reactivación no se pudo hacer: el aviso dice qué pasó y qué hacer.
  void avisarFallaAlReactivar(String texto);

  /// Las piezas de «Mostrar bajas» de [espacioId], una por renglón: el interruptor (solo si hay bajas),
  /// las bajas si está prendido y el aviso si no se pudieron leer. Sin [puedeReactivar] (el espacio o la
  /// casa están dados de baja) las bajas se ven y no se reactivan. [margen] es el aire a los costados
  /// (la hoja de la casa ya trae el suyo).
  List<Widget Function()> piezasDeBajas({
    required String espacioId,
    required bool puedeReactivar,
    required DateTime ahora,
    double margen = 20,
  }) {
    final lectura = ref.watch(bajasDelEspacioProvider(espacioId));
    final saldos = ref.watch(saldosDeBajasDelEspacioProvider(espacioId)).asData?.value ?? const {};
    final bajas = lectura.asData?.value ?? const <PersonaDelEspacio>[];
    return [
      if (bajas.isNotEmpty)
        () => MostrarBajasDePersonas(
          valor: _mostrarBajas,
          alCambiar: (valor) => setState(() => _mostrarBajas = valor),
          margen: margen,
        ),
      if (bajas.isNotEmpty && _mostrarBajas)
        for (final baja in bajas)
          () => FilaBajaDePersona(
            key: ClavesBajasDePersonas.fila(baja.persona.id),
            baja: baja,
            saldoCentavos: saldos[baja.persona.id],
            ahora: ahora,
            reactivando: _reactivando.contains(baja.persona.id),
            alReactivar: puedeReactivar ? () => reactivarPersona(baja) : null,
            margen: margen,
          ),
      if (lectura.hasError)
        () => ErrorBajasDePersonas(
          alReintentar: () => ref.invalidate(bajasDelEspacioProvider(espacioId)),
          margen: margen,
        ),
    ];
  }

  /// «Reactivar» (32D·04): la persona vuelve a la lista y el aviso lo dice (32D·05). Si falla, el
  /// botón vuelve a quedar tocable y el aviso dice qué hacer.
  Future<void> reactivarPersona(PersonaDelEspacio baja) async {
    final id = baja.persona.id;
    if (_reactivando.contains(id)) return;
    // Con la cuenta restringida mientras la pantalla estaba abierta no se reactiva a nadie.
    if (frenaPorCuentaRestringida(context, ref)) return;
    final nombre = FormatoBajaPersona.nombreDePila(baja.persona);
    setState(() => _reactivando.add(id));
    var salio = false;
    try {
      final r = await ref.read(reactivarPersonaUseCaseProvider)(id);
      r.fold((falla) {
        if (mounted) {
          avisarFallaAlReactivar(
            mensajeDeFallaDePersona(falla, TextosBajaPersona.noPudimosReactivar(nombre)),
          );
        }
      }, (_) => salio = true);
    } on Object {
      if (mounted) avisarFallaAlReactivar(TextosBajaPersona.noPudimosReactivar(nombre));
    } finally {
      if (mounted) setState(() => _reactivando.remove(id));
    }
    if (salio && mounted) avisarReactivada(TextosBajaPersona.activaDeNuevo(nombre));
  }
}

/// «Mostrar bajas» (canvas 32D·04): el interruptor que muestra o esconde a las personas dadas de baja.
class MostrarBajasDePersonas extends StatelessWidget {
  const MostrarBajasDePersonas({
    super.key,
    required this.valor,
    required this.alCambiar,
    this.margen = 20,
  });

  final bool valor;
  final ValueChanged<bool> alCambiar;
  final double margen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SwitchListTile(
        key: ClavesBajasDePersonas.mostrar,
        value: valor,
        onChanged: alCambiar,
        contentPadding: EdgeInsets.symmetric(horizontal: margen),
        title: const Text(
          TextosBajaPersona.mostrarBajas,
          style: TextStyle(fontSize: 14, color: ColoresAlta.tinta),
        ),
      ),
    );
  }
}

/// Una persona dada de baja (canvas 32D·04): iniciales y nombre en gris, «Baja el 22/10 · saldo
/// $ 1.200» y «Reactivar». Sin [alReactivar] (el espacio está dado de baja) se ve y no se toca.
class FilaBajaDePersona extends StatelessWidget {
  const FilaBajaDePersona({
    super.key,
    required this.baja,
    required this.saldoCentavos,
    required this.ahora,
    required this.reactivando,
    required this.alReactivar,
    this.margen = 20,
  });

  final PersonaDelEspacio baja;
  final int? saldoCentavos;
  final DateTime ahora;
  final bool reactivando;
  final VoidCallback? alReactivar;
  final double margen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persona = baja.persona;
    final nombre = FormatoPersonas.nombreCompleto(persona);
    final desde = persona.auditoria.deletedAt;
    final detalle = desde == null
        ? ''
        : TextosBajaPersona.bajaEl(desde, ahora, saldoCentavos: saldoCentavos);
    // A 2× el botón no entra al lado del nombre: va debajo.
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final datos = Semantics(
      container: true,
      excludeSemantics: true,
      label: '$nombre. $detalle',
      child: Row(
        children: [
          // El círculo es fijo (36 dp) y las iniciales no dicen nada que el nombre de al lado no diga:
          // no escalan con el texto (partirían en dos renglones) y quedan fuera de la lectura.
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFFF3F1EA), shape: BoxShape.circle),
              child: Text(
                FormatoPersonas.iniciales(persona),
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ColoresAlta.gris,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: lineasDelNombreDePersona(context),
                  overflow: desbordeDelNombreDePersona(context),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ColoresAlta.gris,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detalle, style: theme.textTheme.bodySmall?.copyWith(color: ColoresAlta.gris)),
              ],
            ),
          ),
        ],
      ),
    );
    final boton = alReactivar == null
        ? null
        : reactivando
        ? const _Reactivando()
        : TextButton(
            key: ClavesBajasDePersonas.reactivar(persona.id),
            onPressed: alReactivar,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAlta.azul,
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text(TextosBajaPersona.reactivar),
          );
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: EdgeInsets.symmetric(horizontal: margen, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.extension<ColoresColportaje>()?.borde ?? ColoresAlta.grisFondo,
          ),
        ),
      ),
      child: grande || boton == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                datos,
                if (boton != null) Align(alignment: Alignment.centerRight, child: boton),
              ],
            )
          : Row(
              children: [
                Expanded(child: datos),
                boton,
              ],
            ),
    );
  }
}

/// El lugar de «Reactivar» mientras se escribe: no se puede volver a tocar.
class _Reactivando extends StatelessWidget {
  const _Reactivando();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Semantics(
        liveRegion: true,
        label: TextosBajaPersona.reactivando,
        child: const ExcludeSemantics(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }
}

/// «No pudimos leer las bajas en tu teléfono.» con «Reintentar».
class ErrorBajasDePersonas extends StatelessWidget {
  const ErrorBajasDePersonas({super.key, required this.alReintentar, this.margen = 20});

  final VoidCallback alReintentar;
  final double margen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ClavesBajasDePersonas.error,
      padding: EdgeInsets.fromLTRB(margen, 12, margen, 0),
      child: AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosBajaPersona.noPudimosLeerBajas,
        acciones: Align(
          alignment: Alignment.centerLeft,
          child: EnlaceAlta(texto: TextosPersonas.reintentar, alPresionar: alReintentar),
        ),
      ),
    );
  }
}

/// Cuántos renglones tiene el nombre de una fila de persona: tres, salvo con el texto grande (más de
/// 1,5×), donde no se corta nunca: sin el lector de pantalla no habría otra forma de saber quién es.
int? lineasDelNombreDePersona(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.5 ? null : 3;

/// Con el nombre sin recorte tampoco lleva «…».
TextOverflow desbordeDelNombreDePersona(BuildContext context) =>
    lineasDelNombreDePersona(context) == null ? TextOverflow.clip : TextOverflow.ellipsis;
