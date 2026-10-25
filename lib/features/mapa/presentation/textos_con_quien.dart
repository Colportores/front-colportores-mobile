import '../domain/entities/persona.dart';
import '../domain/entities/persona_del_espacio.dart';
import 'formato_baja.dart';
import 'formato_lista_ubicaciones.dart';
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

  /// El paso de programar una entrevista (todavía no ocurrió: el verbo va en presente).
  static const tituloProgramar = '¿Con quién es la entrevista?';
  static const seguir = 'Seguir';

  /// Solo al programar: la cita queda sin persona (decisión «Sin persona», 23/10). Texto propuesto
  /// (mapa §2: texto/aviso); el canvas no dibuja este paso.
  static const todaviaNoSe = 'Todavía no sé con quién';

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

  /// La segunda línea de una fila cuyo nombre se repite en la lista (HU-UBI-008 permite duplicados):
  /// el teléfono enmascarado de 11·04 («Tel. 099 ••• 412») o, sin teléfono, «Cargada el 12/10». No se
  /// numera: «(1)» y «(2)» no dicen quién es quién. Con [conHora] (esa misma línea también se repite
  /// en otra fila del mismo nombre) suma la hora de alta: «Cargada el 12/10 a las 15:40» o «Tel.
  /// 099 ••• 412 · Cargada el 12/10 a las 15:40».
  static String paraDistinguir(Persona persona, {bool conHora = false}) {
    final conTelefono = _tieneTelefono(persona);
    if (!conHora) {
      return conTelefono
          ? FormatoPersonas.telefonoOculto(persona.telefono)
          : cargadaEl(persona.auditoria.createdAt);
    }
    final carga = cargadaElALas(persona.auditoria.createdAt);
    return conTelefono ? '${FormatoPersonas.telefonoOculto(persona.telefono)} · $carga' : carga;
  }

  static bool _tieneTelefono(Persona persona) => (persona.telefono?.trim() ?? '').isNotEmpty;

  /// «Cargada el 12/10» (día y mes, en hora local).
  static String cargadaEl(DateTime momento) =>
      'Cargada el ${FormatoListaUbicaciones.diaMes(momento)}';

  /// «Cargada el 12/10 a las 15:40» (día, mes y hora, en hora local).
  static String cargadaElALas(DateTime momento) {
    final m = momento.toLocal();
    final hora = '${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}';
    return '${cargadaEl(momento)} a las $hora';
  }

  /// Lo que lee el lector de pantalla de una fila: «Pedro Gómez. Saldo $ 1.200». Con
  /// [nombreRepetido], suma el dato que la distingue: «Pedro Gómez. Teléfono terminado en 412.
  /// Saldo $ 1.200» o «Pedro Gómez. Cargada el 12/10». Con [conHora] suma también la hora de alta
  /// («Pedro Gómez. Cargada el 12/10 a las 15:40»), lo mismo que ve la pantalla.
  static String filaParaLector(
    PersonaDelEspacio p,
    int? saldoCentavos, {
    bool nombreRepetido = false,
    bool conHora = false,
  }) {
    final persona = p.persona;
    final conTelefono = _tieneTelefono(persona);
    final partes = [
      FormatoPersonas.nombreCompleto(persona),
      if (nombreRepetido && conTelefono) FormatoPersonas.telefonoParaLector(persona.telefono),
      if (nombreRepetido && conHora)
        cargadaElALas(persona.auditoria.createdAt)
      else if (nombreRepetido && !conTelefono)
        cargadaEl(persona.auditoria.createdAt),
      if (saldoCentavos != null) saldo(saldoCentavos),
    ];
    return partes.join('. ');
  }

  static String _claveNombre(PersonaDelEspacio p) => FormatoPersonas.nombreCompleto(
    p.persona,
  ).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// Los ids de las personas de [personas] cuyo nombre completo se repite en la lista (sin mirar
  /// mayúsculas ni espacios de más).
  static Set<String> conNombreRepetido(List<PersonaDelEspacio> personas) {
    final cuenta = <String, int>{};
    for (final p in personas) {
      cuenta.update(_claveNombre(p), (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      for (final p in personas)
        if (cuenta[_claveNombre(p)]! > 1) p.persona.id,
    };
  }

  /// Los ids de las personas de [personas] con el nombre repetido cuya segunda línea
  /// ([paraDistinguir] sin hora) también se repite en otra del mismo nombre: esas llevan la hora de
  /// alta. Si coinciden hasta en el minuto, queda el orden de alta de la lista.
  static Set<String> conSegundaLineaRepetida(List<PersonaDelEspacio> personas) {
    final repetidos = conNombreRepetido(personas);
    (String, String) clave(PersonaDelEspacio p) => (_claveNombre(p), paraDistinguir(p.persona));
    final cuenta = <(String, String), int>{};
    for (final p in personas.where((p) => repetidos.contains(p.persona.id))) {
      cuenta.update(clave(p), (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      for (final p in personas)
        if (repetidos.contains(p.persona.id) && cuenta[clave(p)]! > 1) p.persona.id,
    };
  }
}
