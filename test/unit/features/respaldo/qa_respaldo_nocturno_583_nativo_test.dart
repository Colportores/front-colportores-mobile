// QA de #583 (PR #624): lo nativo de iOS no se puede correr en la VM, pero que los tres lugares donde
// vive el identificador de la tarea digan lo mismo sí se puede mirar. Si uno se desvía, iOS nunca
// despierta la app (el error no se ve en ningún test ni en el CI).
import 'dart:io';

import 'package:colportores_mobile/features/respaldo/data/services/programador_nocturno_del_sistema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  final delegado = File('ios/Runner/AppDelegate.swift').readAsStringSync();

  test('el identificador de Dart es el de Info.plist (BGTaskSchedulerPermittedIdentifiers)', () {
    final bloque = RegExp(
      r'<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(bloque, isNotNull);
    final ids = RegExp(r'<string>(.*?)</string>').allMatches(bloque!.group(1)!).map((m) => m[1]);
    expect(ids, contains(nombreTareaRespaldoNocturno));
  });

  test('el identificador de Dart es el que registra AppDelegate.swift', () {
    expect(
      delegado,
      contains('registerBGProcessingTask(withIdentifier: "$nombreTareaRespaldoNocturno")'),
    );
  });

  test('Info.plist declara el modo de fondo «processing»', () {
    final bloque = RegExp(
      r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(bloque, isNotNull);
    expect(bloque!.group(1), contains('<string>processing</string>'));
  });

  test('el registro de la tarea ocurre antes de terminar el arranque', () {
    final registro = delegado.indexOf('registerBGProcessingTask');
    final retorno = delegado.indexOf(
      'return super.application(application, didFinishLaunchingWithOptions',
    );
    expect(registro, greaterThan(0));
    expect(retorno, greaterThan(registro));
  });

  test('el isolate sin UI recibe los plugins (Keychain, conectividad, Google, DB)', () {
    expect(delegado, contains('setPluginRegistrantCallback'));
    expect(delegado, contains('GeneratedPluginRegistrant.register(with: registry)'));
  });

  test('Info.plist sigue siendo un XML bien cerrado', () {
    expect('<plist'.allMatches(plist), hasLength(1));
    expect(plist.trimRight(), endsWith('</plist>'));
    expect('<dict>'.allMatches(plist).length, '</dict>'.allMatches(plist).length);
    expect('<array>'.allMatches(plist).length, '</array>'.allMatches(plist).length);
  });
}
