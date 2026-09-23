#!/usr/bin/env bash
# Verificación completa — la misma secuencia que corre CI. Uso local:
#   docker compose -f compose.dev.yml run --rm flutter scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶ pub get";        flutter pub get
echo "▶ build_runner";   dart run build_runner build
# Solo archivos versionados: excluye *.g.dart (generado, formato propio del generador).
echo "▶ format";         git ls-files -z -- 'lib/*.dart' 'test/*.dart' | xargs -0 dart format --output=none --set-exit-if-changed
# `dart analyze` y no `flutter analyze`: este último no muestra los diagnósticos de plugins, y las
# reglas de Riverpod vienen del plugin (analysis_options.yaml → plugins).
echo "▶ analyze";        dart analyze --fatal-infos
echo "▶ test";           flutter test --coverage
echo "▶ coverage";       bash scripts/coverage_check.sh
echo "✓ todo verde"
