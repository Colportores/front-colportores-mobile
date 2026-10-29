// Los textos y formatos de la ficha de una persona (vista 32B, HU-UBI-009).
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ahora = DateTime(2026, 10, 22, 15);

  group('teléfono', () {
    test('un celular uruguayo se escribe como el canvas', () {
      expect(FormatoFicha.telefonoCompleto('099123456'), '+598 99 123 456');
      expect(FormatoFicha.telefonoCompleto('099 123 456'), '+598 99 123 456');
      expect(FormatoFicha.telefonoEnmascarado('099123456'), '+598 99 *** 456');
    });

    test('otro número se deja como lo escribió y se enmascara por el medio', () {
      expect(FormatoFicha.telefonoCompleto('+54 11 5555 1234'), '+54 11 5555 1234');
      expect(FormatoFicha.telefonoEnmascarado('+54 11 5555 1234'), '+54 *** 234');
      expect(FormatoFicha.telefonoEnmascarado('2900 1122'), '29 *** 122');
    });

    test('un número demasiado corto no muestra ningún dígito', () {
      expect(FormatoFicha.telefonoEnmascarado('1234'), '***');
    });

    test('el máscara nunca deja ver el número entero', () {
      for (final tel in ['099123456', '+5491155551234', '29001122']) {
        final oculto = FormatoFicha.telefonoEnmascarado(tel);
        expect(oculto, isNot(contains(tel.replaceAll('+', ''))));
        expect(oculto, contains('***'));
      }
    });

    test('el lector dice cómo termina mientras está oculto y el número solo al mostrarlo', () {
      expect(
        FormatoFicha.telefonoParaLector('099123456', visible: false),
        'Teléfono terminado en 456',
      );
      expect(
        FormatoFicha.telefonoParaLector('099123456', visible: true),
        'Teléfono +598 99 123 456',
      );
    });
  });

  group('vista previa de la nota', () {
    test('una nota corta va entera', () {
      expect(FormatoFicha.vistaPrevia('  Pidió volver  '), 'Pidió volver');
    });

    test('una de 200 caracteres va entera y una de 201 se corta con «…»', () {
      expect(FormatoFicha.vistaPrevia('a' * 200), 'a' * 200);
      expect(FormatoFicha.vistaPrevia('a' * 201), '${'a' * 200}…');
    });

    test('no parte un emoji por la mitad', () {
      final cortada = FormatoFicha.vistaPrevia('😀' * 250);
      expect(cortada.runes.length, 201);
    });
  });

  group('historial', () {
    final cobro = CobroEnFicha(
      id: 'c',
      fecha: DateTime(2026, 10, 20, 12),
      montoCentavos: 60000,
      efectivo: true,
      numeroTalonario: '0042',
    );
    final entrega = EntregaEnFicha(
      id: 'e',
      fecha: DateTime(2026, 10, 26, 12),
      pendiente: true,
      lineas: const [LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 1)],
    );
    final venta = VentaEnFicha(
      id: 'v',
      fecha: DateTime(2026, 10, 12, 12),
      numeroTalonario: '0042',
      montoCentavos: 120000,
      lineas: const [
        LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1),
        LineaDeFicha(nombre: 'Nuestros Hijos', cantidad: 2),
      ],
    );
    final visita = VisitaEnFicha(
      id: 'i',
      fecha: DateTime(2026, 10, 5, 12),
      resultado: TipoResultadoVisita.entrevista,
    );

    test('los rótulos del canvas', () {
      expect(FormatoFicha.antetitulo(cobro, ahora), '20/10 · COBRO');
      expect(FormatoFicha.antetitulo(entrega, ahora), 'LUN 26/10 · ENTREGA PENDIENTE');
      expect(FormatoFicha.antetitulo(venta, ahora), '12/10 · VENTA 0042');
      expect(FormatoFicha.antetitulo(visita, ahora), '05/10 · VISITA');
    });

    test('los títulos y subtítulos', () {
      expect(FormatoFicha.titulo(visita), 'Entrevista hecha');
      expect(FormatoFicha.titulo(venta), 'Salud y Hogar + Nuestros Hijos × 2');
      expect(FormatoFicha.titulo(entrega), 'Nuestros Hijos × 1');
      expect(FormatoFicha.titulo(cobro), contains('en efectivo'));
      expect(FormatoFicha.subtitulo(cobro), 'Venta 0042');
      expect(FormatoFicha.subtitulo(visita), isNull);
    });

    test('cada resultado de visita tiene su texto', () {
      for (final r in TipoResultadoVisita.values) {
        expect(FormatoFicha.resultadoDeVisita(r), isNotEmpty);
      }
    });

    test('una venta o una entrega sin renglones no queda vacía', () {
      final sinLineas = VentaEnFicha(
        id: 'v2',
        fecha: DateTime(2026, 10, 12),
        numeroTalonario: '1',
        montoCentavos: 0,
        lineas: const [],
      );
      expect(FormatoFicha.titulo(sinLineas), 'Venta');
    });
  });

  group('avisos de solo lectura', () {
    test('persona de baja: el texto del canvas, sin género', () {
      final texto = TextosFicha.avisoSoloLectura(
        ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.personaDeBaja,
          bajaDesde: DateTime(2026, 10, 22),
        ),
        ahora,
      );

      expect(
        texto,
        'María está de baja desde el 22/10. Podés ver su historial, pero no registrar nada.',
      );
    });

    test('depto de baja: el texto del canvas', () {
      final texto = TextosFicha.avisoSoloLectura(
        const ContextoNotasPersona(
          nombre: 'María',
          causa: CausaSoloLectura.espacioDeBaja,
          numeroDepto: '3B',
          direccion: 'Mataojo 2044',
        ),
        ahora,
      );

      expect(
        texto,
        'El depto 3B de Mataojo 2044 está dado de baja. La ficha queda en solo lectura.',
      );
    });

    test('sin datos del lugar no inventa ninguno', () {
      final texto = TextosFicha.avisoSoloLectura(
        const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.espacioDeBaja),
        ahora,
      );

      expect(texto, contains('solo lectura'));
      expect(texto, isNot(contains('null')));
    });

    test('sin depto activo', () {
      final texto = TextosFicha.avisoSoloLectura(
        const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.sinEspacioActivo),
        ahora,
      );

      expect(texto, contains('ningún depto activo'));
      expect(texto, endsWith(TextosFicha.reactivarElDepto));
    });

    test('depto de baja con la ubicación también de baja: dice qué reactivar primero', () {
      const contexto = ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.espacioDeBaja,
        numeroDepto: '3B',
        direccion: 'Mataojo 2044',
      );

      expect(
        TextosFicha.avisoSoloLectura(contexto, ahora, ubicacionDeBaja: true),
        'El depto 3B de Mataojo 2044 está dado de baja. La ficha queda en solo lectura. '
        'Reactivá primero la ubicación desde el mapa.',
      );
      expect(
        TextosFicha.avisoSoloLectura(contexto, ahora),
        isNot(contains(TextosFicha.reactivarPrimeroLaUbicacion)),
      );
    });
  });

  test('los textos con el nombre', () {
    expect(
      TextosFicha.noPudimosLeer('María'),
      'No pudimos leer los datos de María en tu teléfono.',
    );
    expect(TextosFicha.noPudimosLeer(null), contains('la persona'));
    expect(TextosFicha.ayudaSinHistorial('Jorge'), 'Lo que registres con Jorge aparece acá.');
    expect(TextosFicha.verMas(30), 'Ver más (30)');
  });
}
