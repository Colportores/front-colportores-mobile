// Los textos de la hoja de una ubicación y de la gestión de sus deptos (vista 11, HU-UBI-007).
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_espacios.dart';
import 'package:test/test.dart';

import '../../../../helpers/espacios_falsos.dart';

void main() {
  group('del canvas (11·01 a 11·03)', () {
    test('la cuenta: «6 deptos» y «1 depto»', () {
      expect(TextosEspacios.cantidad(6), '6 deptos');
      expect(TextosEspacios.cantidad(1), '1 depto');
      expect(TextosEspacios.cantidad(0), '0 deptos');
    });

    test('el grupo: «PISO 1» en mayúsculas y sin los espacios de los bordes', () {
      expect(TextosEspacios.piso('1'), 'PISO 1');
      expect(TextosEspacios.piso(' pb '), 'PISO PB');
      expect(TextosEspacios.grupoSinPiso, 'SIN PISO');
    });

    test('la fila: «Depto 101» o «Sin número»', () {
      expect(TextosEspacios.depto(espacioDe('e', '101')), 'Depto 101');
      expect(TextosEspacios.depto(espacioDe('e', ' 3B ')), 'Depto 3B');
      expect(TextosEspacios.depto(espacioDe('e', null)), 'Sin número');
      expect(TextosEspacios.depto(espacioDe('e', '   ')), 'Sin número');
    });

    test('el repetido: el texto del canvas y «Ver depto 102 ›»', () {
      expect(
        TextosEspacios.repetido('102', TipoUbicacion.edificio),
        'Ya existe el departamento 102 en este edificio.',
      );
      expect(
        TextosEspacios.repetido(' 4 ', TipoUbicacion.negocio),
        'Ya existe el departamento 4 en este negocio.',
      );
      expect(TextosEspacios.verDepto('102'), 'Ver depto 102 ›');
    });

    test('los botones y las etiquetas', () {
      expect(TextosEspacios.masDepartamento, '+ Departamento');
      expect(TextosEspacios.nuevoDepartamento, 'Nuevo departamento');
      expect(TextosEspacios.numeroObligatorio, 'NÚMERO · OBLIGATORIO');
      expect(TextosEspacios.pisoOpcional, 'PISO · OPCIONAL');
      expect(TextosEspacios.agregar, 'Agregar');
      expect(TextosEspacios.agregarYCargarOtro, 'Agregar y cargar otro');
      expect(TextosEspacios.editarUbicacion(TipoUbicacion.edificio), 'Editar edificio');
      expect(TextosEspacios.editarUbicacion(TipoUbicacion.negocio), 'Editar negocio');
      expect(TextosEspacios.editarUbicacion(TipoUbicacion.casa), 'Editar casa');
    });
  });

  group('la baja de un depto', () {
    test('la pregunta nombra al depto, o dice que no tiene número', () {
      expect(TextosEspacios.preguntaBaja(espacioDe('e', '102')), '¿Dar de baja el depto 102?');
      expect(
        TextosEspacios.preguntaBaja(espacioDe('e', null)),
        '¿Dar de baja este depto sin número?',
      );
    });

    test('el cuerpo habla del edificio o del negocio', () {
      expect(
        TextosEspacios.cuerpoBaja(TipoUbicacion.edificio),
        'Deja de aparecer en la lista del edificio.',
      );
      expect(
        TextosEspacios.cuerpoBaja(TipoUbicacion.negocio),
        'Deja de aparecer en la lista del negocio.',
      );
    });

    test('el lector de pantalla lee la fila como botón «Editar»', () {
      expect(TextosEspacios.filaSemantica(espacioDe('e', '101')), 'Depto 101. Editar.');
      expect(TextosEspacios.filaSemantica(espacioDe('e', null)), 'Sin número. Editar.');
    });

    test('el anuncio de «Agregar y cargar otro»', () {
      expect(TextosEspacios.agregado(' 101 '), 'Depto 101 agregado.');
    });
  });

  group('dados de baja y «Reactivar» (#473)', () {
    test('la cabecera y el lector: «Dados de baja», con la cuenta', () {
      expect(TextosEspacios.dadosDeBaja, 'Dados de baja');
      expect(TextosEspacios.dadosDeBajaSemantica(2), 'Dados de baja, 2 deptos');
      expect(TextosEspacios.dadosDeBajaSemantica(1), 'Dados de baja, 1 depto');
    });

    test('la fila: el piso, y el lector la lee como dada de baja con su «Reactivar»', () {
      expect(TextosEspacios.pisoDeLaFila(' 2 '), 'Piso 2');
      expect(TextosEspacios.filaBajaSemantica(espacioDe('e', '103')), 'Depto 103. Dado de baja.');
      expect(TextosEspacios.filaBajaSemantica(espacioDe('e', null)), 'Sin número. Dado de baja.');
      expect(TextosEspacios.reactivarSemantica(espacioDe('e', '103')), 'Reactivar Depto 103');
    });

    test('el aviso de la reactivación sigue al de la casa (09·04), dicho para un depto', () {
      expect(
        TextosEspacios.reactivado(espacioDe('e', ' 103 '), TipoUbicacion.edificio),
        'Depto 103 reactivado. Vuelve a aparecer en el edificio.',
      );
      expect(
        TextosEspacios.reactivado(espacioDe('e', 'Local 1'), TipoUbicacion.negocio),
        'Depto Local 1 reactivado. Vuelve a aparecer en el negocio.',
      );
    });

    test('un depto sin número no se llama «Depto Sin número»', () {
      expect(
        TextosEspacios.reactivado(espacioDe('e', null), TipoUbicacion.edificio),
        'Depto sin número reactivado. Vuelve a aparecer en el edificio.',
      );
      expect(
        TextosEspacios.reactivarRepetido(espacioDe('e', null), TipoUbicacion.edificio),
        startsWith('No se puede reactivar este depto sin número:'),
      );
    });

    test('el número tomado por otro depto: dice por qué y qué hacer', () {
      expect(
        TextosEspacios.reactivarRepetido(espacioDe('e', '103'), TipoUbicacion.edificio),
        'No se puede reactivar el depto 103: ya hay otro con ese número en este edificio. '
        'Cambiale el número al que está activo y probá de nuevo.',
      );
      expect(
        TextosEspacios.reactivarRepetido(espacioDe('e', '4'), TipoUbicacion.negocio),
        contains('en este negocio.'),
      );
    });

    test('los avisos que guían cuando algo falla', () {
      expect(TextosEspacios.noPudimosReactivar, contains('Probá de nuevo'));
      expect(TextosEspacios.noPudimosDeshacer, contains('desde su edición'));
      expect(TextosEspacios.errorBajas, contains('Probá de nuevo'));
    });
  });
}
