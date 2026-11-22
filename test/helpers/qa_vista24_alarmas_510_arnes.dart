// Arnés de la QA de «Aviso exacto» (#510, PR #617): los estados de la vista 24 en los que puede
// aparecer (o faltar) el aviso «Los recordatorios pueden llegar tarde…», llevados a un tamaño y a una
// escala de texto. El canvas no dibuja este aviso: los estados son los del issue y los que salen de
// cruzarlo con los artboards 24A·03/06 y 24B·01–06.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notificaciones_arnes.dart';

typedef Tamano = ({String nombre, double ancho, double alto});

const tamanos = <Tamano>[
  (nombre: '360x640', ancho: 360, alto: 640),
  (nombre: '412x915', ancho: 412, alto: 915),
];

const escalas = <double>[1.0, 2.0];

class SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => Sesion(
    usuarioId: 'col-1',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );
}

final avisoAlarmas = find.byKey(const Key('alarmas_exactas_aviso'));
final abrirAlarmas = find.byKey(const Key('alarmas_exactas_abrir_ajustes'));
final noAbrenAlarmas = find.byKey(const Key('alarmas_exactas_ajustes_no_abren'));
final interruptorRecordatorios = find.byKey(const Key('pref_recordatorios_interruptor'));
final atrasNotificaciones = find.byKey(const Key('notificaciones_atras'));

const textoAvisoAlarmas =
    'Los recordatorios pueden llegar tarde. Activá «Alarmas y recordatorios» para que suenen a la '
    'hora justa.';
const textoNoAbrenAlarmas =
    'No pudimos abrir los ajustes. Abrí los ajustes del teléfono, buscá esta app y activá '
    '«Alarmas y recordatorios».';

/// Los estados de la vista 24 con (o sin) el aviso de las alarmas exactas.
enum Estado617 {
  avisoSolo('aviso solo (24B·01 + aviso)'),
  avisoNoAbren('aviso + «No pudimos abrir los ajustes»'),
  avisoAbriendo('aviso + abriendo (botón apagado)'),
  avisoNotifSinPedir('aviso + notificaciones apagadas, sin pedir (24A·03)'),
  avisoNotifBloqueadas('aviso + notificaciones bloqueadas (24A·06)'),
  avisoErrorGuardar('aviso + error al guardar (24B·06)'),
  avisoErrorLeerPrefs('aviso + error al leer las preferencias'),
  avisoAnticipacionLarga('aviso + anticipación de 120 min'),
  sinAvisoPermitidas('sin aviso: permiso prendido (24B·01)'),
  sinAvisoRecordatoriosApagados('sin aviso: «Recordatorios de agenda» apagados (24B·02)'),
  cargando('cargando preferencias (24B·05)');

  const Estado617(this.rotulo);
  final String rotulo;
  String get id => name;
}

Telefono telefono617({EstadoAlarmasExactas alarmas = EstadoAlarmasExactas.apagadas}) {
  final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
  t.alarmas.estado = alarmas;
  t.agendas.agendas.add(
    RecordatorioDeVisita(
      agendaId: 'ag-1',
      tipo: TipoAgenda.entrevista,
      direccion: 'Av. Italia 1234',
      fechaProgramada: DateTime.now().add(const Duration(days: 1)),
    ),
  );
  return t;
}

/// Monta la pantalla suelta (con el tema de la app) sobre [t], a [tamano] y con [escala] de texto.
Future<void> montar617(
  WidgetTester tester,
  Telefono t, {
  Tamano tamano = const (nombre: '390x844', ancho: 390, alto: 844),
  double escala = 1,
  bool esperar = true,
}) async {
  fijarTamano(tester, tamano: Size(tamano.ancho, tamano.alto), texto: escala);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...t.overrides, sesionProvider.overrideWith(SesionFija.new)],
      child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Lleva la vista 24 a [estado]. Devuelve el teléfono con el que quedó montada.
Future<Telefono> llevarAlEstado617(
  WidgetTester tester,
  Estado617 estado, {
  required Tamano tamano,
  required double escala,
}) async {
  final t = telefono617(
    alarmas: estado == Estado617.sinAvisoPermitidas
        ? EstadoAlarmasExactas.permitidas
        : EstadoAlarmasExactas.apagadas,
  );
  switch (estado) {
    case Estado617.avisoNotifSinPedir:
      t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
    case Estado617.avisoNotifBloqueadas:
      t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
      t.recuerdo.pedido = PedidoNotificaciones.sistema;
    case Estado617.avisoNoAbren:
      t.alarmas.puedeAbrirAjustes = false;
    case Estado617.avisoAbriendo:
      t.alarmas.ajustesDemorados = Completer<void>();
    case Estado617.avisoErrorLeerPrefs:
      t.preferencias.fallaAlLeer = true;
    case Estado617.avisoAnticipacionLarga:
      t.preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 120);
    case Estado617.sinAvisoRecordatoriosApagados:
      t.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
    case Estado617.cargando:
      t.preferencias.lecturaDemorada = Completer<void>();
    default:
      break;
  }
  await montar617(tester, t, tamano: tamano, escala: escala, esperar: estado != Estado617.cargando);
  switch (estado) {
    case Estado617.avisoNoAbren || Estado617.avisoAbriendo:
      await tester.ensureVisible(abrirAlarmas);
      await tester.tap(abrirAlarmas);
      await tester.pump();
      if (estado == Estado617.avisoNoAbren) await tester.pumpAndSettle();
    case Estado617.avisoErrorGuardar:
      t.preferencias.fallaAlGuardar = true;
      await tester.ensureVisible(interruptorRecordatorios);
      await tester.tap(interruptorRecordatorios);
      await tester.pumpAndSettle();
    default:
      break;
  }
  return t;
}
