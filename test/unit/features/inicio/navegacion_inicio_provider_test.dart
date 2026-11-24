// #649: la pestaña de la pantalla principal vive en `navegacionInicioProvider`, con las intenciones
// «ir a la casa» y «volver al mapa tras guardar».
import 'package:colportores_mobile/features/inicio/presentation/providers/navegacion_inicio_provider.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer contenedor;
  late NavegacionInicioNotifier navegacion;

  setUp(() {
    contenedor = ProviderContainer();
    addTearDown(contenedor.dispose);
    navegacion = contenedor.read(navegacionInicioProvider.notifier);
  });

  NavegacionInicio estado() => contenedor.read(navegacionInicioProvider);

  group('dado el shell recién armado', () {
    test('cuando se lo mira, entonces está en «Hoy» y sin nada pendiente', () {
      expect(estado().actual, PestanaInicio.hoy);
      expect(estado().intencion, isNull);
    });

    test('cuando se elige una pestaña, entonces es la que se ve', () {
      for (final pestana in PestanaInicio.values) {
        navegacion.ir(pestana);
        expect(estado().actual, pestana);
      }
    });
  });

  group('irALaCasa', () {
    test(
      'cuando se pide desde cualquier pestaña, entonces queda «Mapa» y la intención con su hoja',
      () {
        for (final desde in PestanaInicio.values) {
          navegacion.ir(desde);

          navegacion.irALaCasa('ub-1');

          expect(estado().actual, PestanaInicio.mapa, reason: 'desde ${desde.name}');
          expect(estado().intencion!.ubicacionId, 'ub-1');
          expect(estado().intencion!.conSuHoja, isTrue);
        }
      },
    );

    test('cuando se pide dos veces la misma casa, entonces son dos intenciones distintas', () {
      navegacion.irALaCasa('ub-1');
      final primera = estado().intencion;

      navegacion.irALaCasa('ub-1');

      expect(identical(estado().intencion, primera), isFalse);
    });

    test('cuando se pide una casa y enseguida otra, entonces gana la última', () {
      navegacion.irALaCasa('ub-1');
      navegacion.irALaCasa('ub-2');

      expect(estado().intencion!.ubicacionId, 'ub-2');
    });
  });

  group('volverAlMapa (tras guardar)', () {
    test('cuando se pide, entonces queda «Mapa» y la intención sin hoja', () {
      navegacion.ir(PestanaInicio.lista);

      navegacion.volverAlMapa('ub-1');

      expect(estado().actual, PestanaInicio.mapa);
      expect(estado().intencion!.ubicacionId, 'ub-1');
      expect(estado().intencion!.conSuHoja, isFalse);
    });

    test(
      'cuando llega tras «ir a la casa» sin que el mapa lo atienda, entonces gana tras guardar',
      () {
        navegacion.irALaCasa('ub-1');
        navegacion.volverAlMapa('ub-1');

        expect(estado().intencion!.conSuHoja, isFalse);
      },
    );
  });

  group('atendida', () {
    test('cuando el mapa atiende la intención, entonces se limpia y la pestaña se queda', () {
      navegacion.irALaCasa('ub-1');

      navegacion.atendida(estado().intencion!);

      expect(estado().intencion, isNull);
      expect(estado().actual, PestanaInicio.mapa);
    });

    test('cuando llegó otra intención mientras tanto, entonces esa no se pierde', () {
      navegacion.irALaCasa('ub-1');
      final vieja = estado().intencion!;
      navegacion.volverAlMapa('ub-2');

      navegacion.atendida(vieja);

      expect(estado().intencion!.ubicacionId, 'ub-2');
    });
  });

  group('cambiar de pestaña a mano', () {
    test(
      'cuando queda una intención sin atender, entonces se descarta (no se aplica más tarde)',
      () {
        navegacion.irALaCasa('ub-1');

        navegacion.ir(PestanaInicio.agenda);

        expect(estado().actual, PestanaInicio.agenda);
        expect(estado().intencion, isNull);
      },
    );

    test(
      'cuando se elige la pestaña que ya está y no hay nada pendiente, entonces no cambia el estado',
      () {
        navegacion.ir(PestanaInicio.lista);
        final antes = estado();

        navegacion.ir(PestanaInicio.lista);

        expect(identical(estado(), antes), isTrue);
      },
    );
  });

  group('reiniciar', () {
    test('cuando se reinicia, entonces vuelve a «Hoy» y suelta lo pendiente', () {
      navegacion.irALaCasa('ub-1');

      navegacion.reiniciar();

      expect(estado().actual, PestanaInicio.hoy);
      expect(estado().intencion, isNull);
    });
  });
}
