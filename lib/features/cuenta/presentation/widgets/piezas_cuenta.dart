import 'package:flutter/material.dart';

import '../../domain/entities/resumen_de_cuenta.dart';
import '../textos_cuenta.dart';

/// Los colores de Mi Cuenta (vista 33A) que el tema no cubre.
abstract final class ColoresCuenta {
  static const navy = Color(0xFF002856);
  static const azul = Color(0xFF13407A);
  static const azulFondo = Color(0xFFE6EEF8);
  static const ambarFondo = Color(0xFFFBF1DA);
  static const ambarTinta = Color(0xFF6E5212);
  static const verde = Color(0xFF1F6E3A);
  static const rojo = Color(0xFFA8312A);
  static const tinta = Color(0xFF0E1A2B);
  static const gris = Color(0xFF5B6B82);
  static const grisFondo = Color(0xFFF3F1EA);
  static const borde = Color(0xFFE3E7EE);
  static const esqueleto = Color(0xFFEDEBE4);
}

/// El encabezado de la pestaña: «CUENTA» y «Mi Cuenta».
class CabeceraCuenta extends StatelessWidget {
  const CabeceraCuenta({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Text(
              TextosCuenta.eyebrow,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 10,
                letterSpacing: 2,
                color: ColoresCuenta.navy,
              ),
            ),
          ),
          Semantics(
            header: true,
            child: const Text(
              TextosCuenta.titulo,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Qué cifra es: su rótulo, su glifo y sus colores (33A·01).
enum TipoDeCifra {
  enMano(
    rotulo: TextosCuenta.enMano,
    hablado: 'En mano',
    glifo: r'$',
    fondo: ColoresCuenta.ambarFondo,
    tinta: ColoresCuenta.ambarTinta,
  ),
  porCobrar(
    rotulo: TextosCuenta.porCobrar,
    hablado: 'Por cobrar',
    glifo: '◷',
    fondo: ColoresCuenta.azulFondo,
    tinta: ColoresCuenta.azul,
  );

  const TipoDeCifra({
    required this.rotulo,
    required this.hablado,
    required this.glifo,
    required this.fondo,
    required this.tinta,
  });

  final String rotulo;

  /// Cómo lo lee el lector de pantalla.
  final String hablado;
  final String glifo;
  final Color fondo;
  final Color tinta;

  /// «En mano» que creció cierra con «depositalo pronto» (33A·01).
  bool get aconsejaDepositar => this == TipoDeCifra.enMano;

  /// El color de la línea de abajo: verde si lo que se movió es buena noticia, ámbar si hay más
  /// efectivo para depositar, gris si no hay qué comparar, no se movió o subió lo que falta cobrar.
  Color colorDeLaVariacion(int? variacionCentavos) {
    if (variacionCentavos == null || variacionCentavos == 0) return ColoresCuenta.gris;
    if (variacionCentavos < 0) return ColoresCuenta.verde;
    return this == TipoDeCifra.enMano ? ColoresCuenta.ambarTinta : ColoresCuenta.gris;
  }
}

/// Una cifra de Mi Cuenta: su glifo, el rótulo, el total y cuánto cambió contra la semana pasada.
///
/// Con la cifra en cero no hay colores de cuenta: el glifo va gris (33A·04, 33C·03). El lector de
/// pantalla la lee de una vez («En mano, $ 2.400. Subió $ 1.800 contra la semana pasada.»).
class TarjetaDeCifra extends StatelessWidget {
  const TarjetaDeCifra({super.key, required this.tipo, required this.cifra});

  final TipoDeCifra tipo;
  final CifraDeCuenta cifra;

  @override
  Widget build(BuildContext context) {
    final sinNada = cifra.totalCentavos == 0;
    final monto = FormatoCuenta.monto(cifra.totalCentavos);
    final linea = FormatoCuenta.lineaDeVariacion(cifra, aconsejaDepositar: tipo.aconsejaDepositar);
    final hablada = FormatoCuenta.variacionHablada(
      cifra,
      aconsejaDepositar: tipo.aconsejaDepositar,
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${tipo.hablado}, $monto. $hablada.',
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresCuenta.borde),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sinNada ? ColoresCuenta.grisFondo : tipo.fondo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tipo.glifo,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: sinNada ? ColoresCuenta.gris : tipo.tinta,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tipo.rotulo,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.4,
                      color: ColoresCuenta.gris,
                    ),
                  ),
                  Text(
                    monto,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: ColoresCuenta.tinta,
                    ),
                  ),
                  Text(
                    linea,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      color: tipo.colorDeLaVariacion(cifra.variacionCentavos),
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
}

/// La carga (33A·03): un bloque gris por cada tarjeta.
class EsqueletoCuenta extends StatelessWidget {
  const EsqueletoCuenta({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque() => Container(
      height: 74,
      decoration: BoxDecoration(
        color: ColoresCuenta.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosCuenta.cargando,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tipo in TipoDeCifra.values) ...[
                KeyedSubtree(key: Key('cuenta_esqueleto_${tipo.name}'), child: bloque()),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// El error (33A·05): «No pudimos calcular tu cuenta.» y «Reintentar».
class BannerErrorCuenta extends StatelessWidget {
  const BannerErrorCuenta({super.key, required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ColoresCuenta.rojo, width: 1.5),
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
                        color: ColoresCuenta.rojo,
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
                      TextosCuenta.errorCalculo,
                      key: Key('cuenta_error_texto'),
                      style: TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('cuenta_reintentar'),
                  onPressed: alReintentar,
                  style: TextButton.styleFrom(
                    foregroundColor: ColoresCuenta.azul,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text(TextosCuenta.reintentar),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
