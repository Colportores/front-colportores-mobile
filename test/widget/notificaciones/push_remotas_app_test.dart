// HU-NOT-003 (#187) en la app entera: una push que llega con la app abierta se guarda y se avisa
// arriba de la pantalla principal (24C·08); sin sesión no escucha; el toque de la notificación del
// sistema abre la app y marca el aviso como leído.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/push_remotas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/enganches_push_remotas.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auditoria_push_en_memoria.dart';
import '../../helpers/datos_locales_de_push_en_memoria.dart';
import '../../helpers/historial_notificaciones_falsos.dart';
import '../../helpers/notificaciones_arnes.dart';

const _pedido = '3f2b8c1e-9a4d-4e7b-8c1a-5d6e7f8a9b0c';
const _evento = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

final _aviso = find.byKey(const Key('aviso_push_en_app_abrir'));
final _cerrarAviso = find.byKey(const Key('aviso_push_en_app_cerrar'));

Map<String, Object?> _pedidoAutorizado() => {
  'type': 'pedido_autorizado',
  'pedido_id': _pedido,
  'event_id': _evento,
};

Telefono _telefono() => Telefono(estado: EstadoSistemaNotificaciones.activadas);

void main() {
  late PushRemotasEnMemoria push;
  late CentroArnes centro;
  late AuditoriaPushEnMemoria auditoria;

  setUp(() {
    push = PushRemotasEnMemoria();
    centro = CentroArnes();
    auditoria = AuditoriaPushEnMemoria();
  });

  List<Override> extra() => [
    pushRemotasProvider.overrideWithValue(push),
    ...EnganchesPushRemotas.enganches(navigatorKeyColportores),
    ...centro.overrides,
    auditoriaPushRepositoryProvider.overrideWithValue(auditoria),
    datosLocalesDePushRepositoryProvider.overrideWithValue(DatosLocalesDePushEnMemoria()),
  ];

  int sinLeer() => centro.historial.filas.where((n) => !n.leida).length;

  testWidgets('dado que la app está abierta en la pantalla principal, cuando llega el pedido '
      'autorizado, entonces el aviso sale arriba y queda sin leer en el centro', (tester) async {
    await abrirApp(tester, _telefono(), extra: extra());
    expect(principal, findsOneWidget);
    expect(_aviso, findsNothing);

    push.llegaConLaAppAbierta(_pedidoAutorizado());
    await tester.pump(const Duration(milliseconds: 50));

    expect(_aviso, findsOneWidget);
    expect(find.text('Tu pedido fue autorizado'), findsOneWidget);
    expect(sinLeer(), 1);
  });

  testWidgets('dado un aviso arriba, cuando se toca la ✕, entonces se cierra y el aviso queda sin '
      'leer', (tester) async {
    await abrirApp(tester, _telefono(), extra: extra());
    push.llegaConLaAppAbierta(_pedidoAutorizado());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(_cerrarAviso);
    await tester.pump();

    expect(_aviso, findsNothing);
    expect(sinLeer(), 1);
  });

  testWidgets('dado un aviso arriba, cuando se toca, entonces queda leído y se va', (tester) async {
    await abrirApp(tester, _telefono(), extra: extra());
    push.llegaConLaAppAbierta(_pedidoAutorizado());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(_aviso);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpAndSettle();

    expect(_aviso, findsNothing);
    expect(sinLeer(), 0);
    expect(centro.historial.marcadas, ['push-$_evento']);
    expect(
      find.byType(CentroNotificacionesPage),
      findsOneWidget,
      reason: 'sin detalle abre el centro',
    );
  });

  testWidgets('dado que no hay sesión (pantalla de ingreso), cuando llega una push, entonces no se '
      'escucha ni se muestra nada', (tester) async {
    await abrirApp(tester, _telefono(), iniciarSesion: false, extra: extra());
    expect(find.byKey(const Key('login_enviar')), findsOneWidget);

    push.llegaConLaAppAbierta(_pedidoAutorizado());
    await tester.pump(const Duration(milliseconds: 50));

    expect(_aviso, findsNothing);
    expect(push.consultasDeLaQueAbrioLaApp, 0);
    expect(centro.historial.filas, isEmpty);
  });

  testWidgets('dado una push con datos personales, cuando llega, entonces no se muestra nada ni se '
      'guarda, y queda constancia en la auditoría', (tester) async {
    await abrirApp(tester, _telefono(), extra: extra());

    push.llegaConLaAppAbierta({..._pedidoAutorizado(), 'cliente_nombre': 'María Fernández'});
    await tester.pump(const Duration(milliseconds: 50));

    expect(_aviso, findsNothing);
    expect(find.textContaining('María'), findsNothing);
    expect(centro.historial.filas, isEmpty);
    expect(auditoria.descartadas, [
      ['cliente_nombre'],
    ]);
  });

  testWidgets('dado que la app se abrió con el toque de la notificación del sistema, entonces el '
      'aviso queda guardado y leído, sin aviso de arriba', (tester) async {
    push.abrirLaAppConElToque(_pedidoAutorizado());

    await abrirApp(tester, _telefono(), extra: extra());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpAndSettle();

    expect(centro.historial.filas.map((n) => n.titulo), ['Tu pedido fue autorizado']);
    expect(sinLeer(), 0);
    expect(find.byType(CentroNotificacionesPage), findsOneWidget);
    expect(_aviso, findsNothing, reason: 'el toque ya abrió el aviso: no se avisa dos veces');
  });
}
