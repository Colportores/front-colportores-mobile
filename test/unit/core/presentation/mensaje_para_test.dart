import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/presentation/mensaje_para.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mensajePara', () {
    test('sin conexión dice qué hace falta, con la acción de la pantalla', () {
      expect(
        mensajePara(const FailureSinConexion(), accion: 'iniciar sesión'),
        'Necesitás conexión para iniciar sesión',
      );
    });

    test('sin «noPudimos», una falla del servidor conserva su texto', () {
      expect(
        mensajePara(const FailureServidor(status: 400), accion: 'iniciar sesión'),
        const FailureServidor().mensaje,
      );
    });

    test('con «noPudimos», una falla del servidor genérica dice qué pasa y qué hacer', () {
      expect(
        mensajePara(
          const FailureServidor(status: 400),
          accion: 'iniciar sesión',
          noPudimos: 'No pudimos iniciar tu sesión.',
        ),
        'No pudimos iniciar tu sesión. Probá de nuevo en unos minutos.',
      );
    });

    test('con «noPudimos», sin conexión sigue diciendo que hace falta conexión', () {
      expect(
        mensajePara(
          const FailureSinConexion(),
          accion: 'iniciar sesión',
          noPudimos: 'No pudimos iniciar tu sesión.',
        ),
        'Necesitás conexión para iniciar sesión',
      );
    });
  });

  group('mensajeDeServidor', () {
    test('el genérico (sin texto propio ni código técnico) se compone con el «No pudimos …»', () {
      for (final status in <int?>[null, 400, 422, 500]) {
        expect(
          mensajeDeServidor(
            FailureServidor(status: status),
            noPudimos: 'No pudimos crear tu cuenta.',
          ),
          'No pudimos crear tu cuenta. Probá de nuevo en unos minutos.',
        );
      }
    });

    test('un texto propio (el rate limit del 429) se conserva tal cual', () {
      const limite = FailureServidor(
        status: 429,
        mensaje: 'Demasiados intentos. Esperá unos minutos y volvé a probar.',
      );

      expect(
        mensajeDeServidor(limite, noPudimos: 'No pudimos crear tu cuenta.'),
        'Demasiados intentos. Esperá unos minutos y volvé a probar.',
      );
    });
  });
}
