import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import '../../domain/entities/nota_ubicacion.dart';
import '../formato_hoja_casa.dart' show TextosDeptosDeLaCasa;
import '../pages/nota_ubicacion_form_page.dart';
import '../providers/notas_ubicacion_providers.dart';
import '../textos_notas.dart';
import 'piezas_alta.dart' show AvisoAlta, ColoresAlta, EnlaceAlta;
import 'piezas_lista_ubicaciones.dart' show ColoresLista;

/// Las claves con que los tests (y el QA) encuentran lo que dibuja la fila de la nota del depto.
abstract final class ClavesNotaDelDepto {
  static const fila = Key('nota_depto_fila');
  static const agregar = Key('nota_depto_agregar');
  static const editar = Key('nota_depto_editar');
  static const error = Key('nota_depto_error');
  static const reintentar = Key('nota_depto_reintentar');
  static const texto = Key('nota_depto_texto');
}

/// La nota del depto en la hoja del depto como una casa (vista 11, 11N·01, 11N·03 y 11N·05; #290): va
/// arriba de «PERSONAS». Con notas, la más nueva (cortada a tres renglones; la pestaña Notas las
/// muestra enteras) con «Editar»; sin ninguna, «+ Agregar una nota» con su ejemplo. Las dos abren el
/// mismo formulario de las notas del depto (11N·02, 11N·04 y 11N·07).
///
/// - Cargando no dibuja nada (no tapa lo demás); si no se pudo leer, lo dice y ofrece «Reintentar».
/// - Con el depto dado de baja (o sin sesión) la nota se ve, pero no se agrega ni se edita.
/// - Un solo formulario a la vez: un doble toque no abre dos encima.
///
/// **local-only — PII**: el texto vive solo en el teléfono y nunca va a un log.
class FilaNotaDelDepto extends ConsumerStatefulWidget {
  const FilaNotaDelDepto({
    super.key,
    required this.espacioId,
    required this.colportorId,
    required this.soloLectura,
  });

  final String espacioId;

  /// UUID del usuario con la sesión iniciada (`created_by` de las notas nuevas). Sin él no se escribe.
  final String? colportorId;

  /// El lugar está dado de baja: la nota se ve, pero no se agrega ni se edita.
  final bool soloLectura;

  @override
  ConsumerState<FilaNotaDelDepto> createState() => _FilaNotaDelDeptoState();
}

class _FilaNotaDelDeptoState extends ConsumerState<FilaNotaDelDepto> {
  /// Ya se está abriendo el formulario: un segundo toque no abre otro encima. Es un campo: corta aunque
  /// el toque llegue antes de que se vuelva a dibujar.
  var _abriendo = false;

  bool get _puedeEscribir => !widget.soloLectura && widget.colportorId != null;

  Future<void> _abrir({NotaUbicacion? nota}) async {
    final colportorId = widget.colportorId;
    if (_abriendo || colportorId == null) return;
    if (frenaPorCuentaRestringida(context, ref)) return;
    _abriendo = true;
    try {
      await NotaDeptoFormPage.abrir(
        context,
        espacioId: widget.espacioId,
        colportorId: colportorId,
        nota: nota,
      );
    } finally {
      _abriendo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notas = ref.watch(notasDeDeptoProvider(widget.espacioId));
    if (notas.hasError) {
      return AvisoAlta(
        key: ClavesNotaDelDepto.error,
        color: ColoresAlta.rojo,
        glyph: '!',
        texto: TextosNotas.noPudimosLeerDelDepto,
        acciones: Align(
          alignment: Alignment.centerLeft,
          child: EnlaceAlta(
            key: ClavesNotaDelDepto.reintentar,
            texto: TextosNotas.reintentar,
            alPresionar: () => ref.invalidate(notasDeDeptoProvider(widget.espacioId)),
          ),
        ),
      );
    }
    final lista = notas.value;
    if (lista == null) return const SizedBox.shrink();
    final nota = lista.where((n) => !n.estaBorrada).firstOrNull;
    if (nota == null) {
      // Un depto de baja o sin sesión no tiene nada que ofrecer sin notas.
      return _puedeEscribir ? _SinNota(alTocar: _abrir) : const SizedBox.shrink();
    }
    return _ConNota(
      texto: nota.texto,
      alEditar: _puedeEscribir ? () => _abrir(nota: nota) : null,
    );
  }
}

/// El borde y el fondo de la fila (canvas, `Bloques` · card): blanco, borde de 1 dp y radio 14.
BoxDecoration _decoracion() => BoxDecoration(
  color: Colors.white,
  border: Border.all(color: const Color(0xFFE3E7EE)),
  borderRadius: BorderRadius.circular(14),
);

/// El cuadrado del lápiz de la izquierda.
class _Lapiz extends StatelessWidget {
  const _Lapiz();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        TextosDeptosDeLaCasa.lapizDeLaNota,
        style: TextStyle(fontSize: 14, color: ColoresLista.tinta, height: 1),
      ),
    );
  }
}

/// 11N·01: «+ Agregar una nota» con «Por ejemplo, «timbre roto, tocar fuerte»».
class _SinNota extends StatelessWidget {
  const _SinNota({required this.alTocar});

  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '${TextosDeptosDeLaCasa.agregarUnaNota}. ${TextosDeptosDeLaCasa.agregarUnaNotaAyuda}',
      onTap: alTocar,
      excludeSemantics: true,
      child: Material(
        key: ClavesNotaDelDepto.fila,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ClavesNotaDelDepto.agregar,
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _Lapiz(),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          TextosDeptosDeLaCasa.agregarUnaNota,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: ColoresAlta.azul,
                          ),
                        ),
                        Text(
                          TextosDeptosDeLaCasa.agregarUnaNotaAyuda,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            height: 1.35,
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
    );
  }
}

/// 11N·03 y 11N·05: la nota más nueva, cortada a tres renglones, con «Editar» a la derecha.
class _ConNota extends StatelessWidget {
  const _ConNota({required this.texto, required this.alEditar});

  final String texto;

  /// `null`: el depto está en solo lectura y no hay «Editar».
  final VoidCallback? alEditar;

  static const _maximoDeRenglones = 3;

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          TextosDeptosDeLaCasa.notaDelDepto,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            letterSpacing: .44,
            color: ColoresAlta.gris,
          ),
        ),
        Text(
          texto,
          key: ClavesNotaDelDepto.texto,
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
    );
    return Container(
      key: ClavesNotaDelDepto.fila,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: _decoracion(),
      child: Row(
        children: [
          const _Lapiz(),
          const SizedBox(width: 12),
          // El lector dice la nota entera: la fila la corta a tres renglones.
          Expanded(
            child: Semantics(
              container: true,
              label: '${TextosDeptosDeLaCasa.notaDelDepto}. $texto',
              excludeSemantics: true,
              child: contenido,
            ),
          ),
          if (alEditar != null)
            // «Editar» es un objetivo de 48 dp.
            TextButton(
              key: ClavesNotaDelDepto.editar,
              onPressed: alEditar,
              style: TextButton.styleFrom(
                foregroundColor: ColoresAlta.azul,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosDeptosDeLaCasa.editarLaNota),
            ),
        ],
      ),
    );
  }
}
