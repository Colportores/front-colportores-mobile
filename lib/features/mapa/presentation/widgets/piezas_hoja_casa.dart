import 'package:flutter/material.dart';

import '../../domain/entities/nota_del_lugar.dart';
import '../../domain/entities/persona.dart';
import '../formato_hoja_casa.dart';
import '../textos_personas.dart';
import 'piezas_alta.dart' show ColoresAlta;
import 'piezas_lista_ubicaciones.dart' show ColoresLista, textoGrande;

/// Las claves con que los tests (y el QA) encuentran lo que dibuja la hoja de la casa.
abstract final class ClavesHojaCasa {
  static const titulo = Key('hoja_casa_titulo');
  static const subtitulo = Key('hoja_casa_subtitulo');
  static const persona = Key('hoja_casa_persona');
  static const cobrar = Key('hoja_casa_cobrar');
  static const abrirPersona = Key('hoja_casa_abrir_persona');
  static const pestanas = Key('hoja_casa_pestanas');
  static const agregarPersona = Key('hoja_casa_agregar_persona');
  static const sinPersonas = Key('hoja_casa_sin_personas');
  static const personaGuardada = Key('hoja_casa_persona_guardada');
  static const listaDePersonas = Key('hoja_casa_lista_de_personas');
  static Key pestana(String id) => Key('hoja_casa_pestana_$id');
  static const nota = Key('hoja_casa_nota');
  static const registrarVisita = Key('hoja_casa_registrar_visita');
  static const cerrar = Key('hoja_casa_cerrar');
}

/// El azul navy del botón y del avatar (canvas `#002856`).
const _navy = Color(0xFF002856);
const _fondoNota = Color(0xFFF2F6FB);
const _bordeFila = Color(0xFFE3E7EE);

/// El borde y el fondo de las filas de la hoja (canvas, `Bloques` · card): blanco, borde de 1 dp y
/// radio 14.
BoxDecoration _decoracionDeFila() => BoxDecoration(
  color: Colors.white,
  border: Border.all(color: _bordeFila),
  borderRadius: BorderRadius.circular(14),
);

/// La persona del lugar (C·01 y C·02): su avatar con las iniciales, el nombre, lo que debe y, si debe,
/// «$ Cobrar». Sin [alCobrar] no se dibuja el botón (no hay a dónde llevar: HU-UBI-003).
///
/// [alCobrar] se dispara **una sola vez por vez** (lo decide quien arma la fila, que comparte la guarda
/// con «Registrar visita»): acá solo se apaga el botón mientras [ocupada].
///
/// En la pestaña Personas (C·02) la fila puede llevar [detalle] (la línea de abajo, por ejemplo
/// «Entrevista dada el 05/10», cuando no debe nada) y [alAbrir]: tocarla abre la ficha de la persona
/// (vista 32 B). Con [alAbrir] la fila es un botón y, si no tiene «$ Cobrar», lleva el «›» del canvas;
/// sin [alAbrir] no se puede tocar y no lleva «›».
class FilaPersonaDeLaCasa extends StatelessWidget {
  const FilaPersonaDeLaCasa({
    super.key,
    required this.persona,
    this.saldoCentavos,
    this.detalle,
    this.alCobrar,
    this.alAbrir,
    this.ocupada = false,
  });

  final Persona persona;

  /// Lo que debe, en centavos; `null` si no debe o no se sabe (no se escribe «$ 0»).
  final int? saldoCentavos;

  /// La línea de abajo cuando no debe nada; `null` = ninguna. Si debe, manda «Debe $ 1.200».
  final String? detalle;

  /// «$ Cobrar»; `null` = no se ofrece.
  final VoidCallback? alCobrar;

  /// Tocar la fila (abre la ficha); `null` = la fila no se toca.
  final VoidCallback? alAbrir;

  /// Hay una acción en curso: «$ Cobrar» y la fila quedan apagados.
  final bool ocupada;

  @override
  Widget build(BuildContext context) {
    final nombre = FormatoPersonas.nombreCompleto(persona);
    final debe = saldoCentavos == null ? null : TextosHojaCasa.debe(saldoCentavos!);
    final linea = debe ?? detalle;
    final cobra = saldoCentavos != null && alCobrar != null;
    final grande = textoGrande(context);
    final abre = alAbrir != null;
    final avatar = ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: _navy, shape: BoxShape.circle),
        child: Text(
          FormatoPersonas.iniciales(persona),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1,
          ),
        ),
      ),
    );
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          nombre,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ColoresLista.tinta,
          ),
        ),
        if (linea != null)
          Text(
            linea,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              height: 1.4,
              color: ColoresLista.grisTexto,
            ),
          ),
      ],
    );
    final etiqueta = linea == null ? nombre : '$nombre. $linea';
    final Widget izquierda = abre
        ? Semantics(
            key: ClavesHojaCasa.persona,
            container: true,
            button: true,
            enabled: !ocupada,
            label: etiqueta,
            onTap: ocupada ? null : alAbrir,
            excludeSemantics: true,
            child: InkWell(
              key: ClavesHojaCasa.abrirPersona,
              borderRadius: BorderRadius.circular(10),
              onTap: ocupada ? null : alAbrir,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: textos),
                    if (!cobra) ...[
                      const SizedBox(width: 8),
                      const Text(
                        '›',
                        style: TextStyle(fontSize: 20, height: 1, color: ColoresLista.chevron),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
        : Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  key: ClavesHojaCasa.persona,
                  container: true,
                  label: etiqueta,
                  excludeSemantics: true,
                  child: textos,
                ),
              ),
            ],
          );
    // El texto de la persona y «$ Cobrar» son nodos aparte: el lector de pantalla tiene que poder
    // llegar al botón (un solo nodo con los hijos excluidos lo dejaría fuera).
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _decoracionDeFila(),
      child: grande && cobra
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                izquierda,
                _BotonCobrar(nombre: nombre, alPresionar: ocupada ? null : alCobrar),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: izquierda),
                if (cobra) ...[
                  const SizedBox(width: 8),
                  _BotonCobrar(nombre: nombre, alPresionar: ocupada ? null : alCobrar),
                ],
              ],
            ),
    );
  }
}

/// «$ Cobrar»: la píldora del canvas (borde de 1,5, texto azul) con un objetivo táctil de 48 dp: toda
/// el área de 48 dp responde, aunque la píldora dibujada sea más baja.
class _BotonCobrar extends StatelessWidget {
  const _BotonCobrar({required this.nombre, required this.alPresionar});

  final String nombre;
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    final habilitado = alPresionar != null;
    return Semantics(
      container: true,
      button: true,
      enabled: habilitado,
      label: TextosHojaCasa.cobrarA(nombre),
      onTap: alPresionar,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ClavesHojaCasa.cobrar,
          customBorder: const StadiumBorder(),
          onTap: alPresionar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              widthFactor: 1,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: habilitado ? ColoresAlta.grisBorde : _bordeFila,
                      width: 1.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    TextosHojaCasa.cobrar,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: habilitado ? ColoresAlta.azul : ColoresLista.grisTexto,
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

/// La nota más reciente del lugar (C·01): el lápiz, «NOTA DEL LUGAR» y el texto. Un texto largo se
/// corta a tres renglones; el lector de pantalla lo dice entero y la pestaña Notas (C·05) lo muestra
/// completo.
///
/// **local-only — PII**: el texto vive solo en el teléfono y nunca va a un log.
class FilaNotaDelLugar extends StatelessWidget {
  const FilaNotaDelLugar({super.key, required this.nota});

  final NotaDelLugar nota;

  static const _maximoDeRenglones = 3;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ClavesHojaCasa.nota,
      container: true,
      label: '${_sinMayusculas(TextosHojaCasa.notaDelLugar)}. ${nota.texto}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _decoracionDeFila(),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _fondoNota, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                '✎',
                style: TextStyle(fontSize: 14, color: ColoresLista.tinta, height: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    TextosHojaCasa.notaDelLugar,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      letterSpacing: .44,
                      color: ColoresAlta.gris,
                    ),
                  ),
                  Text(
                    nota.texto,
                    maxLines: _maximoDeRenglones,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ColoresLista.tinta,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «NOTA DEL LUGAR» → «Nota del lugar» para el lector (que deletrea las mayúsculas).
  static String _sinMayusculas(String texto) =>
      texto.isEmpty ? texto : texto[0] + texto.substring(1).toLowerCase();
}

/// «✓  Registrar visita» (C·01): el único botón de la hoja, píldora azul navy de 56 dp. Mientras
/// [ocupado] queda apagado (un doble toque no abre dos veces «¿Qué pasó?»).
class BotonRegistrarVisita extends StatelessWidget {
  const BotonRegistrarVisita({super.key, required this.alPresionar, this.ocupado = false});

  final VoidCallback alPresionar;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: !ocupado,
      label: TextosHojaCasa.registrarVisita,
      onTap: ocupado ? null : alPresionar,
      excludeSemantics: true,
      child: FilledButton(
        key: ClavesHojaCasa.registrarVisita,
        onPressed: ocupado ? null : alPresionar,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          backgroundColor: _navy,
          disabledBackgroundColor: _navy.withValues(alpha: .6),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text(
          '${TextosHojaCasa.tildeDelBoton}  ${TextosHojaCasa.registrarVisita}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
