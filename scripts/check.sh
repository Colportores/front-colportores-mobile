#!/usr/bin/env bash
# Verificación completa — la misma secuencia que corre CI. Uso local:
#   docker compose -f compose.dev.yml run --rm flutter scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶ pub get";        flutter pub get
echo "▶ build_runner";   dart run build_runner build
echo "▶ format";         dart format --output=none --set-exit-if-changed lib test
echo "▶ analyze";        flutter analyze --fatal-infos
echo "▶ custom_lint";    dart run custom_lint --fatal-infos
echo "▶ test";           flutter test --coverage
echo "▶ coverage";       bash scripts/coverage_check.sh
echo "✓ todo verde"
