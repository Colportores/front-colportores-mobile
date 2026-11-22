import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../mapa/presentation/providers/hoja_casa_providers.dart'
    show ContextoDeCobro, VentaRegistradaEnLaCasa;
import '../../mapa/presentation/providers/personas_providers.dart';
import '../../mapa/presentation/textos_personas.dart' show FormatoPersonas;
import '../../ventas/domain/entities/venta_abierta.dart';
import '../../ventas/domain/services/reglas_de_venta_que_crece.dart';
import '../../ventas/presentation/providers/ventas_providers.dart';
import '../../ventas/presentation/textos_venta_que_crece.dart';
import '../../ventas/presentation/widgets/hoja_a_que_venta.dart';
import 'widgets/flujo_entrevista.dart';

/// Cuánto se espera la lectura de las ventas abiertas antes de decir que no se pudo.
const _topeDeLectura = Duration(seconds: 3);

/// «Sumar un libro» de la hoja de la casa y de la ficha de la persona (vista 42, 42B·09A y 09B;
/// HU-VEN-001, «Venta crece»): lo que enchufa `sumarUnLibroDesdeLaCasaProvider`.
///
/// 1. Lee las ventas abiertas de la persona. Con **una** sigue directo; con **varias** abre «¿A qué
///    venta lo sumás?» con la más reciente elegida; sin ninguna (se cerró mientras la hoja estaba
///    abierta) lo dice: el libro va en una venta nueva.
/// 2. Sigue en [FlujoEntrevista.sumarALaVenta] (42B·09C → 09D → el mapa).
///
/// Devuelve [VentaRegistradaEnLaCasa] si se sumó (la hoja de la casa se cierra y el mapa queda libre)
/// y `false` si no (no cambió nada). Lanza si no hay dónde sumar (la casa sin depto elegido o sin
/// sesión): quien lo abre lo dice con su propio aviso.
abstract final class FlujoVentaQueCrece {
  static Future<Object?> abrir(
    BuildContext context,
    ContextoDeCobro datos, {
    required String? colportorId,
  }) async {
    final espacioId = datos.espacioId;
    final colportor = colportorId?.trim() ?? '';
    if (espacioId == null || colportor.isEmpty) {
      throw StateError('Sumar un libro necesita una casa o un depto y una sesión iniciada');
    }
    final contenedor = ProviderScope.containerOf(context, listen: false);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    void avisar(String texto) => mensajero
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));

    final persona = await _personaDe(contenedor, espacioId, datos.personaId);
    List<VentaAbierta> abiertas;
    try {
      abiertas = await contenedor
          .read(ventaQueCreceRepositoryProvider)
          .observarAbiertasDe(datos.personaId)
          .first
          .timeout(_topeDeLectura);
    } on Object {
      // Nada del error al aviso: puede traer datos de la venta (convenciones §7.5).
      avisar(TextosVentaQueCrece.noPudimosLeer);
      return false;
    }
    if (!context.mounted) return false;

    final VentaAbierta venta;
    switch (PasoVentaQueCrece.de(abiertas)) {
      case SinVentaAbierta():
        avisar(TextosVentaQueCrece.sinVentaAbierta(persona?.nombre));
        return false;
      case UnaVentaAbierta(venta: final unica):
        venta = unica;
      case VariasVentasAbiertas(:final ventas):
        final elegida = await mostrarHojaAQueVenta(
          context,
          ventas: ventas,
          subtitulo: [
            if ((persona?.completo ?? '').isNotEmpty) persona!.completo,
            if ((persona?.lugar ?? '').isNotEmpty) persona!.lugar,
          ].join(' · '),
        );
        if (elegida == null || !context.mounted) return false;
        venta = elegida;
    }

    final sumada = await FlujoEntrevista.sumarALaVenta(
      context,
      contenedor,
      colportorId: colportor,
      espacioId: espacioId,
      venta: venta,
    );
    return sumada ? const VentaRegistradaEnLaCasa() : false;
  }

  /// El nombre de pila, el completo y dónde vive la persona [personaId] de [espacioId], o `null` si
  /// ya no está o no se pudo leer: «Sumar un libro» no depende de eso.
  static Future<({String nombre, String completo, String lugar})?> _personaDe(
    ProviderContainer contenedor,
    String espacioId,
    String personaId,
  ) async {
    try {
      var lugar = '';
      final contexto = (await contenedor.read(espacioRepositoryProvider).buscar(espacioId)).fold(
        (_) => null,
        (c) => c,
      );
      if (contexto != null) {
        lugar = FormatoPersonas.dondeEstaElEspacio(contexto.espacio, contexto.ubicacion);
      }
      final personas = await contenedor
          .read(personaRepositoryProvider)
          .observarDelEspacio(espacioId)
          .first
          .timeout(_topeDeLectura);
      for (final p in personas) {
        if (p.persona.id == personaId) {
          return (
            nombre: p.persona.nombre,
            completo: FormatoPersonas.nombreCompleto(p.persona),
            lugar: lugar,
          );
        }
      }
    } on Object {
      return null;
    }
    return null;
  }
}
