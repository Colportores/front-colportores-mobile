import 'package:flutter/material.dart';

import '../../../auth/presentation/widgets/borde_discontinuo.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/resumen_del_depto.dart';
import '../formato_espacios.dart' show TextosEspacios;
import '../formato_hoja_casa.dart';
import 'piezas_alta.dart' show AvisoAlta, ColoresAlta;
import 'piezas_lista_ubicaciones.dart' show ColoresLista, InsigniaEstadoCasa;

/// Las claves de los deptos en la hoja de la casa (vista 39, N·04, N·06, C·09 y C·10).
abstract final class ClavesDeptosDeLaCasa {
  static const lista = Key('hoja_casa_deptos');
  static const rotulo = Key('hoja_casa_deptos_rotulo');
  static const cuenta = Key('hoja_casa_deptos_cuenta');
  static const texto = Key('hoja_casa_deptos_texto');
  static const agregar = Key('hoja_casa_deptos_agregar');
  static const tarjetaAgregar = Key('hoja_casa_deptos_tarjeta_agregar');
  static const seguir = Key('hoja_casa_deptos_seguir');
  static const volverDeN04 = Key('hoja_casa_deptos_volver_n04');
  static const vacio = Key('hoja_casa_deptos_vacio');
  static const error = Key('hoja_casa_deptos_error');
  static const reintentar = Key('hoja_casa_deptos_reintentar');
  static const volver = Key('hoja_casa_volver_a_los_deptos');
  static const personas = Key('hoja_casa_depto_personas');
  static const agregarPersona = Key('hoja_casa_depto_agregar_persona');

  /// La fila del depto [espacioId].
  static Key fila(String espacioId) => Key('hoja_casa_depto_$espacioId');
}

/// En qué paso está la lista de deptos de la hoja.
enum PasoDeptos {
  /// N·04 «Edificio: sus deptos»: el edificio recién registrado; se suman los deptos que se van a
  /// visitar y «Seguir».
  agregando,

  /// N·06 «Edificio: elegir el depto»: el edificio recién registrado, después de «Seguir»; tocar un
  /// depto abre «¿Qué pasó?» para ese depto (N·07).
  eligiendo,

  /// C·09 «Edificio: sus deptos»: un edificio (o un negocio) que ya estaba; tocar un depto lo abre como
  /// una casa (C·10).
  existente,
}

/// Los deptos de un edificio en la hoja de la casa (vista 39): el rótulo con la cuenta y
/// «+ Agregar depto», y una fila por depto con el color y el símbolo de su estado.
///
/// - [PasoDeptos.agregando] (N·04): arriba «Sumá los deptos que vas a visitar…», «DEPTOS» con la
///   cuenta a la derecha, las filas con el piso, la tarjeta punteada «Agregar depto · Número y piso» y
///   «Seguir».
/// - [PasoDeptos.eligiendo] (N·06) y [PasoDeptos.existente] (C·09): «3 DEPTOS» con «+ Agregar depto» a
///   la derecha y las filas. Sin deptos, lo dice y qué hacer.
///
/// Sin [alAgregar] no se ofrece agregar (la casa de baja, o sin saber quién es el colportor). Mientras
/// [ocupado] nada se toca: una acción a la vez.
class DeptosDeLaCasa extends StatelessWidget {
  const DeptosDeLaCasa({
    super.key,
    required this.espacios,
    required this.resumenes,
    required this.paso,
    required this.ahora,
    required this.ocupado,
    required this.alElegir,
    this.alAgregar,
    this.alSeguir,
    this.alVolver,
  });

  /// Los deptos activos, en el orden de la lista (por piso y por número).
  final List<Espacio> espacios;

  /// El resumen de cada depto; `null` si no se pudo leer (las filas no dicen estado).
  final Map<String, ResumenDelDepto>? resumenes;
  final PasoDeptos paso;
  final DateTime ahora;
  final bool ocupado;
  final ValueChanged<Espacio>? alElegir;
  final VoidCallback? alAgregar;

  /// «Seguir» de N·04.
  final VoidCallback? alSeguir;

  /// «Volver» de N·04: el edificio ya quedó guardado (vista 41, «Registrar»), así que cierra la hoja
  /// y vuelve al mapa como la ✕, sin deshacer el alta (decisión §2 del 11/11, P1 de
  /// `452-impl-261111-1400`).
  final VoidCallback? alVolver;

  @override
  Widget build(BuildContext context) {
    final agregando = paso == PasoDeptos.agregando;
    final recien = paso != PasoDeptos.existente;
    return Column(
      key: ClavesDeptosDeLaCasa.lista,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        if (agregando)
          const Text(
            TextosDeptosDeLaCasa.sumaLosDeptos,
            key: ClavesDeptosDeLaCasa.texto,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.4,
              color: ColoresLista.grisTexto,
            ),
          ),
        _Rotulo(
          texto: agregando
              ? TextosDeptosDeLaCasa.deptos
              : TextosDeptosDeLaCasa.cantidad(espacios.length),
          cuenta: agregando ? '${espacios.length}' : null,
          alAgregar: agregando || alAgregar == null || ocupado ? null : alAgregar,
          conAgregar: !agregando && alAgregar != null,
        ),
        if (espacios.isEmpty && !agregando) const _SinDeptos(),
        for (final espacio in espacios)
          FilaDeptoDeLaCasa(
            key: ClavesDeptosDeLaCasa.fila(espacio.id),
            espacio: espacio,
            resumen: resumenes?[espacio.id],
            detalle: FormatoDeptosDeLaCasa.detalle(
              espacio,
              resumenes?[espacio.id],
              ahora,
              recienRegistrado: recien,
              conEstado: !agregando,
            ),
            alTocar: alElegir == null || ocupado ? null : () => alElegir!(espacio),
          ),
        if (agregando && alAgregar != null)
          _TarjetaAgregarDepto(alTocar: ocupado ? null : alAgregar),
        if (agregando && alSeguir != null)
          FilledButton(
            key: ClavesDeptosDeLaCasa.seguir,
            onPressed: ocupado ? null : alSeguir,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: const StadiumBorder(),
              backgroundColor: const Color(0xFF002856),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosDeptosDeLaCasa.seguir, textAlign: TextAlign.center),
          ),
        if (agregando && alVolver != null)
          TextButton(
            key: ClavesDeptosDeLaCasa.volverDeN04,
            onPressed: ocupado ? null : alVolver,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAlta.azul,
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosDeptosDeLaCasa.volver, textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

/// «6 DEPTOS» con «+ Agregar depto» a la derecha (C·09, N·06), o «DEPTOS» con la cuenta (N·04). Con el
/// texto grande, «+ Agregar depto» baja debajo del rótulo en vez de recortarse.
class _Rotulo extends StatelessWidget {
  const _Rotulo({
    required this.texto,
    required this.cuenta,
    required this.alAgregar,
    required this.conAgregar,
  });

  final String texto;
  final String? cuenta;
  final VoidCallback? alAgregar;

  /// Se dibuja «+ Agregar depto» (apagado si [alAgregar] es `null`).
  final bool conAgregar;

  static const _estilo = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 11,
    letterSpacing: 1.4,
    color: ColoresAlta.gris,
  );

  @override
  Widget build(BuildContext context) {
    final rotulo = Semantics(
      header: true,
      child: Text(texto, key: ClavesDeptosDeLaCasa.rotulo, style: _estilo),
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: [
        rotulo,
        if (cuenta != null) Text(cuenta!, key: ClavesDeptosDeLaCasa.cuenta, style: _estilo),
        if (conAgregar)
          TextButton(
            key: ClavesDeptosDeLaCasa.agregar,
            onPressed: alAgregar,
            style: TextButton.styleFrom(
              foregroundColor: ColoresAlta.azul,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosDeptosDeLaCasa.agregarDepto),
          ),
      ],
    );
  }
}

/// La fila de un depto (vista 39, `dep()`): la insignia de su estado, «Depto 1A» y la línea de abajo, y
/// «›». Mide 54 dp o más. Es un botón para el lector de pantalla, que la lee entera. Sin [alTocar] queda
/// apagada.
class FilaDeptoDeLaCasa extends StatelessWidget {
  const FilaDeptoDeLaCasa({
    super.key,
    required this.espacio,
    required this.resumen,
    required this.detalle,
    required this.alTocar,
  });

  final Espacio espacio;

  /// `null`: no se sabe su estado y no se dibuja insignia.
  final ResumenDelDepto? resumen;
  final String detalle;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final titulo = TextosEspacios.depto(espacio);
    final sinNumero = espacio.sinNumero;
    final estado = resumen?.estado;
    return Semantics(
      button: true,
      enabled: alTocar != null,
      label: detalle.isEmpty ? titulo : '$titulo. $detalle',
      onTap: alTocar,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresLista.grisBorde),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: estado == null ? null : InsigniaEstadoCasa(estado: estado),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titulo,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: sinNumero ? ColoresLista.grisTexto : ColoresLista.tinta,
                            fontStyle: sinNumero ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        if (detalle.isNotEmpty)
                          Text(
                            detalle,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              height: 1.35,
                              color: ColoresLista.grisTexto,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('›', style: TextStyle(fontSize: 22, color: ColoresLista.grisTexto)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La tarjeta punteada de N·04: «+» y «Agregar depto · Número y piso». Abre el alta del depto (vista
/// 11·02).
class _TarjetaAgregarDepto extends StatelessWidget {
  const _TarjetaAgregarDepto({required this.alTocar});

  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: alTocar != null,
      label: '${TextosDeptosDeLaCasa.agregarDeptoTarjeta}. ${TextosDeptosDeLaCasa.numeroYPiso}',
      onTap: alTocar,
      excludeSemantics: true,
      child: BordeDiscontinuo(
        color: const Color(0xFFCFD6E1),
        radio: 14,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ClavesDeptosDeLaCasa.tarjetaAgregar,
            onTap: alTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ColoresAlta.azulFondo,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ColoresAlta.azul,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            TextosDeptosDeLaCasa.agregarDeptoTarjeta,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: ColoresAlta.azul,
                            ),
                          ),
                          Text(
                            TextosDeptosDeLaCasa.numeroYPiso,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              color: ColoresLista.grisTexto,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El edificio sin deptos: lo dice y qué hacer (a confirmar, el canvas no lo dibuja).
class _SinDeptos extends StatelessWidget {
  const _SinDeptos();

  @override
  Widget build(BuildContext context) => const Padding(
    key: ClavesDeptosDeLaCasa.vacio,
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          TextosDeptosDeLaCasa.sinDeptos,
          style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text(
          TextosDeptosDeLaCasa.sinDeptosQueHacer,
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: ColoresLista.grisTexto),
        ),
      ],
    ),
  );
}

/// No se pudieron leer los deptos: el aviso y «Reintentar».
class ErrorDeptosDeLaCasa extends StatelessWidget {
  const ErrorDeptosDeLaCasa({super.key, required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) => Column(
    key: ClavesDeptosDeLaCasa.error,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      const AvisoAlta(
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosDeptosDeLaCasa.errorLectura,
      ),
      OutlinedButton(
        key: ClavesDeptosDeLaCasa.reintentar,
        onPressed: alReintentar,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text(TextosDeptosDeLaCasa.reintentar),
      ),
    ],
  );
}
