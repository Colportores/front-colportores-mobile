// HU-VIS-006 (#152): agendar una cobranza en la ubicación alternativa, sin pantalla. El caso de uso
// lleva `ubicacion_alt_id` a la agenda, solo para una cobranza, y el recordatorio menciona la dirección
// de la alternativa (HU-NOT-002).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/destino_de_cobranza.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/texto_recordatorio.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/agendar_visita_arnes.dart';

void main() {
  late AgendaRepositorioQueAgenda repo;
  late RecordatoriosEnMemoria recordatorios;
  late AgendarVisitaUseCase caso;
  var n = 0;

  final trabajo = Ubicacion(
    id: 'ub-trabajo',
    tipo: TipoUbicacion.negocio,
    calle: 'Av. Italia',
    numero: '2810',
    lat: -34.9,
    lon: -56.16,
    ciudadId: 'mvd',
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
    ),
  );

  setUp(() {
    n = 0;
    repo = AgendaRepositorioQueAgenda();
    recordatorios = RecordatoriosEnMemoria();
    caso = AgendarVisitaUseCase(
      repo,
      recordatorios,
      generarId: () => 'id-${++n}',
      ahora: () => DateTime(2026, 10, 23, 14, 35),
    );
  });

  AgendarVisitaParams cobranza({
    TipoAgenda tipo = TipoAgenda.cobranza,
    String? alternativa,
    String direccion = 'Mataojo 2044',
    String? persona = 'ep-maria',
  }) => AgendarVisitaParams(
    ids: caso.nuevosIds(),
    espacioId: 'esp-1',
    espacioPersonaId: persona,
    colportorId: 'col-1',
    tipo: tipo,
    fechaProgramada: DateTime(2026, 10, 24, 14, 30),
    direccion: direccion,
    ubicacionAltId: alternativa,
  );

  group('Agendar cobranza alternativa (HU-VIS-006)', () {
    test('dada la alternativa de María, cuando se agenda la cobranza, entonces la agenda lleva la '
        'ubicación y el recordatorio la dirección de la alternativa', () async {
      final destino = DestinoDeCobranza.de(UbicacionAlternativaVigente(trabajo));

      final r = await caso(
        cobranza(alternativa: destino.ubicacionAltId, direccion: destino.direccionDelAviso),
      );

      expect(r.isRight(), isTrue);
      expect(repo.recibidas.single.agenda.ubicacionAltId, 'ub-trabajo');
      final aviso = recordatorios.programados.values.single;
      expect(aviso.direccion, 'Av. Italia 2810');
      expect(
        TextoRecordatorio.cuerpo(
          tipo: aviso.tipo,
          direccion: aviso.direccion,
          fechaProgramada: aviso.fechaProgramada,
        ),
        contains('Cobranza en Av. Italia 2810'),
      );
    });

    test('dada una cobranza sin alternativa, cuando se agenda, entonces no lleva ubicación y el '
        'aviso usa la dirección de la casa', () async {
      await caso(cobranza());

      expect(repo.recibidas.single.agenda.ubicacionAltId, isNull);
      expect(recordatorios.programados.values.single.direccion, 'Mataojo 2044');
    });

    test(
      'dada una alternativa en blanco, cuando se agenda, entonces cuenta como ninguna',
      () async {
        await caso(cobranza(alternativa: '   '));

        expect(repo.recibidas.single.agenda.ubicacionAltId, isNull);
      },
    );

    test('dada una entrevista con alternativa, cuando se agenda, entonces falla por validación sin '
        'tocar la DB ni el aviso', () async {
      final r = await caso(cobranza(tipo: TipoAgenda.entrevista, alternativa: 'ub-trabajo'));

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureValidacion>());
      expect((falla! as FailureValidacion).campos.keys, contains('ubicacionAlternativa'));
      expect(repo.recibidas, isEmpty);
      expect(recordatorios.programados, isEmpty);
    });

    test('dada la alternativa rechazada por la DB, cuando se agenda, entonces no programa aviso y '
        'al reintentar con los mismos ids sale bien', () async {
      repo.fallas.add(
        const FailureValidacion(
          campos: {'ubicacionAlternativa': 'La ubicación alternativa ya no está activa.'},
        ),
      );
      final p = cobranza(alternativa: 'ub-trabajo');

      final primera = await caso(p);
      expect(primera.isLeft(), isTrue);
      expect(recordatorios.programados, isEmpty);

      final segunda = await caso(p);
      expect(segunda.isRight(), isTrue);
      expect(repo.cuantasQuedaron, 1);
      expect(recordatorios.programados, hasLength(1));
    });

    test(
      'dado un doble toque, cuando llegan dos pedidos iguales, entonces queda una sola agenda',
      () async {
        final p = cobranza(alternativa: 'ub-trabajo');

        await Future.wait([caso(p), caso(p)]);

        expect(repo.cuantasQuedaron, 1);
      },
    );

    test('dos alternativas distintas seguidas no se pisan', () async {
      await caso(cobranza(alternativa: 'ub-a', persona: 'ep-a'));
      await caso(cobranza(alternativa: 'ub-b', persona: 'ep-b'));

      expect([
        for (final g in repo.guardadas.values) g.ubicacionAltId,
      ], unorderedEquals(['ub-a', 'ub-b']));
    });

    test('los params con distinta alternativa no son iguales', () {
      final ids = caso.nuevosIds();
      AgendarVisitaParams con(String? alt) => AgendarVisitaParams(
        ids: ids,
        espacioId: 'e',
        colportorId: 'c',
        tipo: TipoAgenda.cobranza,
        fechaProgramada: DateTime(2026, 10, 24),
        ubicacionAltId: alt,
      );

      expect(con('a'), isNot(con('b')));
      expect(con('a'), con('a'));
    });
  });
}
