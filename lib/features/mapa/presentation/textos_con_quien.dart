import '../domain/entities/persona_del_espacio.dart';
import 'formato_baja.dart';
import 'textos_personas.dart';

/// Los textos del paso «¿Con quién?» de la vista 39 (R·04 y C·07). Los del canvas van tal cual; los
/// que el canvas no dibuja reusan los de las vistas de personas (32A y 11·04), para que el mismo caso
/// diga lo mismo en todas (mapa §2: coherencia entre pantallas).
abstract final class TextosConQuien {
  /// R·04, la casa sin personas (el tiempo del verbo es el de «Entrevista dada»: la entrevista ya empezó).
  static const tituloSinPersonas = '¿Con quién es la entrevista?';

  /// C·07, la casa con personas.
  static const tituloConPersonas = '¿Con quién fue la entrevista?';

  /// R·04: «Grecia 3307 · con el nombre alcanza». Sin la dirección (todavía no se leyó), arranca en
  /// mayúscula.
  static String ayudaSinPersonas(String? donde) =>
      donde == null ? 'Con el nombre alcanza' : '$donde · con el nombre alcanza';

  static const empezar = 'Empezar entrevista';
  static const volver = 'Volver';
  static const alguienNuevo = '+ Alguien nuevo';
  static const alguienNuevoAyuda = 'Con el nombre alcanza';

  /// Mientras se guarda el nombre de R·04.
  static const empezando = 'Guardando…';

  // Lo que el canvas no dibuja: cargar, no poder leer y no poder guardar (los de 11·04 y 32A).
  static const cargando = TextosPersonas.cargando;
  static const noPudimosLeer = TextosPersonas.noPudimosLeer;
  static const reintentar = TextosPersonas.reintentar;
  static const noPudimosGuardar = TextosPersonas.noPudimosGuardar;

  /// «Saldo $ 1.200». El canvas de la 39 escribe «$ 1.200»; las vistas aprobadas de baja escriben
  /// «$U 1.200» (pendiente mapa §2: coherencia entre pantallas). Un solo punto para cambiarlo.
  static String saldo(int centavos) =>
      'Saldo ${FormatoBaja.monto(centavos).replaceFirst(r'$U', r'$')}';

  /// Lo que lee el lector de pantalla de una fila: «Pedro Gómez. Saldo $ 1.200».
  static String filaParaLector(PersonaDelEspacio p, int? saldoCentavos) {
    final nombre = FormatoPersonas.nombreCompleto(p.persona);
    return saldoCentavos == null ? nombre : '$nombre. ${saldo(saldoCentavos)}';
  }
}
