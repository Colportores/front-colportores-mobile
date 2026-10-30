import 'package:flutter/material.dart';

import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/services/cuenta_de_persona.dart';
import '../../domain/services/filtro_de_historial.dart';
import '../textos_baja_persona.dart';
import '../textos_ficha_persona.dart';
import 'piezas_alta.dart';

// Las piezas de la ficha de una persona (vista 32B, HU-UBI-009): el teléfono, la cuenta, la última nota
// y las filas del historial.

/// Claves para los tests.
abstract final class ClavesFicha {
  static const telefono = Key('ficha_telefono');
  static const botonVer = Key('ficha_ver_telefono');
  static const botonLlamar = Key('ficha_llamar');
  static const botonAgregarTelefono = Key('ficha_agregar_telefono');
  static const menu = Key('ficha_menu');
  static const opcionEditar = Key('ficha_opcion_editar');
  static const opcionBaja = Key('ficha_opcion_baja');
  static const cuenta = Key('ficha_cuenta');
  static const acciones = Key('ficha_acciones');
  static const botonAgendarCobranza = Key('ficha_agendar_cobranza');
  static const botonRegistrarEntrega = Key('ficha_registrar_entrega');
  static const sinMovimientos = Key('ficha_sin_movimientos');
  static const notas = Key('ficha_notas');
  static const botonNota = Key('ficha_boton_nota');
  static const ultimaNota = Key('ficha_ultima_nota');
  static const historial = Key('ficha_historial');
  static const verMas = Key('ficha_ver_mas');
  static const sinResultados = Key('ficha_sin_resultados');
  static const hero = Key('ficha_hero');
  static const botonRegistrarVisita = Key('ficha_registrar_visita');
  static const aviso = Key('ficha_aviso');
  static const botonReactivar = Key('ficha_reactivar');
  static const botonReactivarDepto = Key('ficha_reactivar_depto');
  static const cargando = Key('ficha_cargando');
  static const error = Key('ficha_error');

  static Key fila(String id) => Key('ficha_fila_$id');

  static Key filtro(FiltroDeHistorial f) => Key('ficha_filtro_${f.name}');
}

const _estiloRotulo = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10,
  letterSpacing: 1.4,
  color: ColoresAlta.gris,
);

/// El rótulo de una sección («NOTAS · SOLO EN TU TELÉFONO», «HISTORIAL») con, si hay, su acción a la
/// derecha. Con el texto al 200 % el rótulo y la acción se reparten el renglón (`Flexible`): ninguno
/// desborda.
class RotuloDeSeccion extends StatelessWidget {
  const RotuloDeSeccion({
    super.key,
    required this.texto,
    this.accion,
    this.alAccion,
    this.claveAccion,
  });

  final String texto;
  final String? accion;
  final VoidCallback? alAccion;
  final Key? claveAccion;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Semantics(header: true, child: Text(texto, style: _estiloRotulo)),
        ),
        if (accion != null && alAccion != null)
          Flexible(
            child: TextButton(
              key: claveAccion,
              onPressed: alAccion,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: ColoresAlta.azul,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: Text(accion!, textAlign: TextAlign.end),
            ),
          ),
      ],
    );
  }
}

/// El cuadro blanco con borde de las filas de la ficha.
class _Cuadro extends StatelessWidget {
  const _Cuadro({required this.hijo, this.fondo = Colors.white});

  final Widget hijo;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresAlta.grisBorde),
      ),
      child: hijo,
    );
  }
}

/// El recuadro con el glyph de una fila (✓, ★, $, ☏, ✎).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.glyph, this.fondo, this.color, this.radio = 8});

  final String glyph;
  final Color? fondo;
  final Color? color;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: fondo ?? ColoresAlta.grisFondo,
          borderRadius: BorderRadius.circular(radio),
        ),
        alignment: Alignment.center,
        child: Text(
          glyph,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color ?? ColoresAlta.tinta,
          ),
        ),
      ),
    );
  }
}

/// El teléfono de la persona (32B·01, 32B·02 y 32B·05): enmascarado con «Ver · Llamar», entero con
/// «Llamar» (y la nota de que se vuelve a ocultar), o «Sin teléfono» con «Agregar» si se puede editar.
///
/// - Con el texto grande los botones bajan debajo del número en vez de apretarlo.
/// - El lector de pantalla dice «Teléfono terminado en 456» mientras está oculto, y el número entero
///   solo cuando se lo mostró.
class TarjetaTelefono extends StatelessWidget {
  const TarjetaTelefono({
    super.key,
    required this.telefono,
    required this.visible,
    required this.alVer,
    required this.alLlamar,
    required this.alAgregar,
  });

  /// El teléfono guardado, o `null`/vacío si no tiene.
  final String? telefono;
  final bool visible;
  final VoidCallback alVer;

  /// `null` apaga «Llamar» (ya se está abriendo el marcador).
  final VoidCallback? alLlamar;

  /// «Agregar» (la edición de la persona); `null` si no se ofrece.
  final VoidCallback? alAgregar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valor = telefono?.trim() ?? '';
    final tiene = valor.isNotEmpty;
    final grande = MediaQuery.textScalerOf(context).scale(14) > 20;
    final texto = !tiene
        ? TextosFicha.sinTelefono
        : visible
        ? FormatoFicha.telefonoCompleto(valor)
        : FormatoFicha.telefonoEnmascarado(valor);
    final lector = !tiene
        ? TextosFicha.sinTelefono
        : FormatoFicha.telefonoParaLector(valor, visible: visible);

    final acciones = <Widget>[
      if (tiene && !visible)
        _Enlace(clave: ClavesFicha.botonVer, texto: TextosFicha.ver, alTocar: alVer),
      if (tiene)
        _Enlace(clave: ClavesFicha.botonLlamar, texto: TextosFicha.llamar, alTocar: alLlamar),
      if (!tiene && alAgregar != null)
        _Enlace(
          clave: ClavesFicha.botonAgregarTelefono,
          texto: TextosFicha.agregarTelefono,
          alTocar: alAgregar,
        ),
    ];

    final cuerpo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: lector,
          child: ExcludeSemantics(
            child: Text(
              texto,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tiene ? null : ColoresAlta.gris,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        if (tiene && visible)
          const Text(
            TextosFicha.seVuelveAOcultar,
            style: TextStyle(fontSize: 12, color: ColoresAlta.gris),
          ),
      ],
    );

    return KeyedSubtree(
      key: ClavesFicha.telefono,
      child: _Cuadro(
        hijo: grande
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Glyph(glyph: '☏', radio: 10),
                      const SizedBox(width: 12),
                      Expanded(child: cuerpo),
                    ],
                  ),
                  if (acciones.isNotEmpty) Wrap(spacing: 4, children: acciones),
                ],
              )
            : Row(
                children: [
                  const _Glyph(glyph: '☏', radio: 10),
                  const SizedBox(width: 12),
                  Expanded(child: cuerpo),
                  ..._conPuntoMedio(acciones),
                ],
              ),
      ),
    );
  }

  static List<Widget> _conPuntoMedio(List<Widget> acciones) => [
    for (var i = 0; i < acciones.length; i++) ...[
      if (i > 0) const Text('·', style: TextStyle(color: ColoresAlta.gris)),
      acciones[i],
    ],
  ];
}

class _Enlace extends StatelessWidget {
  const _Enlace({required this.clave, required this.texto, required this.alTocar});

  final Key clave;
  final String texto;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: clave,
      onPressed: alTocar,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: ColoresAlta.azul,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(texto),
    );
  }
}

/// Lo que compró, recibió y pagó (32B·01): comprado, entregado, pagado y saldo. El saldo va en negrita.
class TarjetaCuenta extends StatelessWidget {
  const TarjetaCuenta({super.key, required this.cuenta});

  final ResumenCuentaPersona cuenta;

  @override
  Widget build(BuildContext context) {
    final filas = <(String, String, bool)>[
      (TextosFicha.comprado, FormatoBajaPersona.monto(cuenta.compradoCentavos), false),
      (TextosFicha.entregado, TextosBajaPersona.entregas(cuenta), false),
      (TextosFicha.pagado, FormatoBajaPersona.monto(cuenta.pagadoCentavos), false),
      (TextosFicha.saldo, FormatoBajaPersona.monto(cuenta.saldoCentavos), true),
    ];
    return KeyedSubtree(
      key: ClavesFicha.cuenta,
      child: _Cuadro(
        hijo: Column(
          children: [
            for (final (rotulo, valor, fuerte) in filas)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          rotulo,
                          style: TextStyle(
                            fontSize: 14,
                            color: fuerte ? ColoresAlta.tinta : ColoresAlta.gris,
                            fontWeight: fuerte ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          valor,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 14,
                            fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
                            color: ColoresAlta.tinta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Las acciones rápidas bajo la cuenta (32B·01, HU-VEN-005): «+ Agendar cobranza» y «Registrar entrega»,
/// sin salir de la ficha. Con [ocupado] (ya se está abriendo algo) quedan apagadas: un segundo toque no
/// abre otra pantalla encima. [conEntrega] en `false`: «Registrar entrega» no se dibuja, porque un botón
/// sin a dónde llevar no se muestra (HU-UBI-003).
class AccionesRapidasDeLaFicha extends StatelessWidget {
  const AccionesRapidasDeLaFicha({
    super.key,
    required this.alAgendarCobranza,
    required this.alRegistrarEntrega,
    this.conCobranza = true,
    this.conEntrega = true,
    this.ocupado = false,
  });

  final VoidCallback alAgendarCobranza;
  final VoidCallback alRegistrarEntrega;

  /// Hay saldo que cobrar; sin él no se ofrece «+ Agendar cobranza».
  final bool conCobranza;

  /// Hay entregas pendientes y el caso de uso está disponible; si no, no se ofrece «Registrar entrega».
  final bool conEntrega;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ClavesFicha.acciones,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (conCobranza)
          _AccionRapida(
            clave: ClavesFicha.botonAgendarCobranza,
            texto: TextosFicha.agendarCobranza,
            alTocar: ocupado ? null : alAgendarCobranza,
          ),
        if (conEntrega)
          _AccionRapida(
            clave: ClavesFicha.botonRegistrarEntrega,
            texto: TextosFicha.registrarEntrega,
            alTocar: ocupado ? null : alRegistrarEntrega,
          ),
      ],
    );
  }
}

class _AccionRapida extends StatelessWidget {
  const _AccionRapida({required this.clave, required this.texto, required this.alTocar});

  final Key clave;
  final String texto;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      key: clave,
      label: Text(texto),
      onPressed: alTocar,
      backgroundColor: Colors.white,
      side: const BorderSide(color: ColoresAlta.grisBorde),
      labelStyle: const TextStyle(
        color: ColoresAlta.tinta,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

/// La cuenta de quien todavía no tiene ventas ni pagos (HU-UBI-009, «Sin movimientos aún»): ocupa el lugar
/// de [TarjetaCuenta]. Sin ventas no hay nada que sumar, y decirlo evita que parezca que la ficha no
/// terminó de cargar.
class SinMovimientosDeCuenta extends StatelessWidget {
  const SinMovimientosDeCuenta({super.key});

  @override
  Widget build(BuildContext context) {
    return const KeyedSubtree(
      key: ClavesFicha.sinMovimientos,
      child: _Cuadro(
        hijo: Text(
          TextosFicha.sinMovimientos,
          style: TextStyle(fontSize: 14, color: ColoresAlta.gris),
        ),
      ),
    );
  }
}

/// La última nota (32B·01): el día y «1 DE 2», y las primeras 200 caracteres. Se toca entera para abrir
/// todas las notas.
class TarjetaUltimaNota extends StatelessWidget {
  const TarjetaUltimaNota({
    super.key,
    required this.rotulo,
    required this.texto,
    required this.alTocar,
  });

  final String rotulo;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '$rotulo. $texto',
      onTap: alTocar,
      excludeSemantics: true,
      child: InkWell(
        key: ClavesFicha.ultimaNota,
        borderRadius: BorderRadius.circular(14),
        onTap: alTocar,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: _Cuadro(
            fondo: ColoresAlta.azulFondo,
            hijo: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph(glyph: '✎', radio: 10, fondo: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rotulo, style: _estiloRotulo),
                      const SizedBox(height: 2),
                      Text(texto, style: const TextStyle(fontSize: 14, height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('›', style: TextStyle(fontSize: 18, color: ColoresAlta.gris)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila del historial (32B·01): visita, venta, entrega o cobro, con su glyph, la línea chica de
/// arriba, el título y, si hay, la de abajo. No se toca: el detalle de cada una no está en esta vista.
/// MOSTRAR con Todo, Con saldo y Entrega pendiente (32B-03): se elige una sola opción.
class FiltroDelHistorial extends StatelessWidget {
  const FiltroDelHistorial({
    super.key,
    required this.opciones,
    required this.elegido,
    required this.alElegir,
  });

  final List<FiltroDeHistorial> opciones;
  final FiltroDeHistorial elegido;
  final ValueChanged<FiltroDeHistorial> alElegir;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(child: Text(TextosFicha.mostrar, style: _estiloRotulo)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in opciones)
              Semantics(
                selected: f == elegido,
                button: true,
                label: TextosFicha.lectorFiltro(f, elegido: f == elegido),
                excludeSemantics: true,
                // Con `excludeSemantics` se descarta la acción del chip: se declara acá.
                onTap: () => alElegir(f),
                child: ChoiceChip(
                  key: ClavesFicha.filtro(f),
                  label: Text(TextosFicha.filtro(f)),
                  selected: f == elegido,
                  showCheckmark: false,
                  selectedColor: esquema.primary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: f == elegido ? esquema.primary : ColoresAlta.grisBorde),
                  labelStyle: TextStyle(
                    color: f == elegido ? esquema.onPrimary : ColoresAlta.tinta,
                    fontWeight: FontWeight.w500,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => alElegir(f),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class FilaDeHistorial extends StatelessWidget {
  const FilaDeHistorial({super.key, required this.movimiento, required this.ahora, this.alTocar});

  final MovimientoDeFicha movimiento;
  final DateTime ahora;

  /// Lo que pasa al tocar la fila (la venta abre su devolución, HU-VEN-004); `null`: la fila no se
  /// toca.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final (glyph, fondo, color) = switch (m) {
      VisitaEnFicha() => ('✓', ColoresAlta.verde, Colors.white),
      VentaEnFicha() => ('★', ColoresAlta.verde, Colors.white),
      CobroEnFicha() => (r'$', ColoresAlta.azul, Colors.white),
      EntregaEnFicha() => ('⇢', ColoresAlta.grisFondo, ColoresAlta.tinta),
    };
    final pendiente = m is EntregaEnFicha && m.pendiente;
    final sub = FormatoFicha.subtitulo(m);
    final cuadro = _Cuadro(
      hijo: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Glyph(glyph: glyph, fondo: fondo, color: color, radio: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FormatoFicha.antetitulo(m, ahora),
                  style: _estiloRotulo.copyWith(
                    color: pendiente ? ColoresAlta.ambar : ColoresAlta.gris,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  FormatoFicha.titulo(m),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                ),
                if (sub != null)
                  Text(sub, style: const TextStyle(fontSize: 13, color: ColoresAlta.gris)),
              ],
            ),
          ),
          if (alTocar != null)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 2),
              child: Icon(Icons.chevron_right, color: ColoresAlta.gris, size: 22),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: alTocar != null,
      onTap: alTocar,
      label: FormatoFicha.paraLector(m, ahora),
      excludeSemantics: true,
      child: KeyedSubtree(
        key: ClavesFicha.fila(m.id),
        child: alTocar == null
            ? cuadro
            : InkWell(onTap: alTocar, borderRadius: BorderRadius.circular(14), child: cuadro),
      ),
    );
  }
}

/// La ficha de quien todavía no tiene visitas ni ventas (32B·05): un ícono, qué pasa y, si se puede,
/// «Registrar visita».
class FichaSinHistorial extends StatelessWidget {
  const FichaSinHistorial({super.key, required this.nombre, required this.alRegistrarVisita});

  final String nombre;

  /// `null`: no se ofrece (persona de baja, o sin destino para registrar).
  final VoidCallback? alRegistrarVisita;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ClavesFicha.hero,
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const _Glyph(glyph: '▦', radio: 28),
          const SizedBox(height: 14),
          Text(
            TextosFicha.sinHistorialTitulo,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            TextosFicha.ayudaSinHistorial(nombre),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (alRegistrarVisita != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              key: ClavesFicha.botonRegistrarVisita,
              onPressed: alRegistrarVisita,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
              child: const Text(TextosFicha.registrarVisita, textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mientras la ficha no llegó (32B·06): cuatro bloques grises. Lo dice el lector de pantalla.
class CargandoFicha extends StatelessWidget {
  const CargandoFicha({super.key, required this.nombre});

  final String? nombre;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesFicha.cargando,
      liveRegion: true,
      label: TextosFicha.cargando(nombre),
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (final alto in const [56.0, 170.0, 64.0, 64.0])
              Container(
                height: alto,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                decoration: BoxDecoration(
                  color: ColoresAlta.grisFondo,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
