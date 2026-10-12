#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJETO="${1:-$HOME/Documentos/foco_simples}"

echo "Foco Simples - aplicação dos arquivos de referência"
echo "Projeto alvo: $PROJETO"
echo

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERRO: Flutter não encontrado no PATH." >&2
  echo "Instale/configure o Flutter antes de continuar." >&2
  exit 1
fi

if [[ ! -f "$PROJETO/pubspec.yaml" || ! -f "$PROJETO/lib/main.dart" ]]; then
  echo "ERRO: projeto Flutter não encontrado em: $PROJETO" >&2
  echo
  echo "Este pacote NÃO cria do zero toda a estrutura Android do Foco Simples."
  echo "Ele aplica o main.dart de referência sobre um projeto Flutter existente."
  echo
  echo "Você pode informar outro caminho:"
  echo "  ./aplicar_linux.sh /caminho/para/seu/projeto"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$PROJETO/lib/main.dart.backup_$STAMP"

echo "Criando backup:"
echo "  $BACKUP"
cp "$PROJETO/lib/main.dart" "$BACKUP"

echo "Aplicando arquivos..."
cp "$DIR/arquivos/main.dart" "$PROJETO/lib/main.dart"

cd "$PROJETO"

echo
echo "Executando flutter pub get..."
flutter pub get

echo
echo "Analisando lib/main.dart..."
flutter analyze lib/main.dart || {
  echo
  echo "ATENÇÃO: flutter analyze encontrou problemas."
  echo "O backup foi preservado em:"
  echo "  $BACKUP"
  exit 1
}

echo
echo "Arquivos aplicados com sucesso."
echo
echo "Para testar no aparelho:"
echo "  flutter run"
echo
echo "Para gerar APK:"
echo "  flutter build apk --release"
echo
echo "Para gerar AAB para Google Play:"
echo "  flutter build appbundle --release"
echo
echo "IMPORTANTE:"
echo "- não publique android/key.properties"
echo "- não publique arquivos .jks/.keystore"
echo "- confira a configuração nativa Android usada para notificações/alertas"
