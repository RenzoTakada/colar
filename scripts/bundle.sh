#!/bin/zsh
# Monta build.noindex/Colar.app a partir do binário do SwiftPM (sem Xcode). A pasta .noindex fica fora do Spotlight,
# então a cópia de build não aparece como um segundo "Colar". Assina com um certificado "Apple Development" do
# keychain, se houver: a permissão de Acessibilidade (sem ela o Colar não cola) fica presa à assinatura, e com
# certificado ela sobrevive a cada build novo. Sem certificado (ou com COLAR_ADHOC=1), assina ad hoc.
# Uso: scripts/bundle.sh [debug|release] [install]
set -e
cd "$(dirname "$0")/.."
CFG=${1:-release}
# Caminhos de compilação mapeados para "." para o binário não carregar o caminho da máquina de quem compilou.
RAIZ=$(pwd)
swift build -c "$CFG" --product Colar -Xswiftc -file-prefix-map -Xswiftc "$RAIZ=." -Xswiftc -debug-prefix-map -Xswiftc "$RAIZ=." 2>&1 | grep -E "error|warning: unre|Build complete" || true
[ "${pipestatus[1]}" -eq 0 ] || { echo "build falhou: nada instalado"; exit 1; }
BIN=".build/$CFG/Colar"
[ -x "$BIN" ] || { echo "binário não encontrado: $BIN"; exit 1; }

VERSAO=0.0.1
BUILD=$(date +%Y%m%d%H%M)
APP="build.noindex/Colar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Colar"
[ -f design/Colar.icns ] && cp design/Colar.icns "$APP/Contents/Resources/Colar.icns"
# Sons de copiar e colar (par "papel"), gerados por design/sons/gerar.py
cp design/sons/copiar.wav design/sons/colar.wav "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Colar</string>
  <key>CFBundleDisplayName</key><string>Colar</string>
  <key>CFBundleIdentifier</key><string>app.colar</string>
  <key>CFBundleExecutable</key><string>Colar</string>
  <key>CFBundleIconFile</key><string>Colar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSAO</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>app.colar</string>
    <key>CFBundleURLSchemes</key><array><string>colar</string></array>
  </dict></array>
  <key>NSHumanReadableCopyright</key><string>Colar, licença MIT</string>
</dict></plist>
PLIST

# Primeiro certificado "Apple Development" válido; sem ele, cai no ad hoc e avisa (a Acessibilidade vai se perder).
IDENT=""
[ -z "${COLAR_ADHOC:-}" ] && IDENT=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
if [ -n "$IDENT" ]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENT" "$APP"
  echo "assinado com Apple Development"
else
  codesign --force --sign - "$APP"
  echo "AVISO: sem certificado Apple Development, assinado ad hoc (Acessibilidade se perde a cada build)"
fi
codesign --verify --strict "$APP"

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSREG -u "$APP" >/dev/null 2>&1 || true   # a cópia de build não entra no Launchpad nem no Spotlight
echo "pronto: $APP ($VERSAO, build $BUILD)"

if [[ " $* " == *" install "* ]]; then
  pkill -x Colar 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/Colar.app && cp -R "$APP" /Applications/Colar.app
  xattr -dr com.apple.quarantine /Applications/Colar.app 2>/dev/null || true
  $LSREG -f /Applications/Colar.app >/dev/null 2>&1 || true
  echo "instalado: /Applications/Colar.app (a anterior foi substituída)"
fi
