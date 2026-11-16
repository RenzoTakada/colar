#!/bin/zsh
# Testes do Colar. Sai com 0 só se tudo passou; cada bloco imprime ok/FALHA.
# Nunca mexe no clipboard real (os checks usam um pasteboard nomeado).
set -u
cd "$(dirname "$0")/.."
falhas=0; total=0
check() { total=$((total+1)); if eval "$2"; then echo "ok   $1"; else echo "FALHA $1"; falhas=$((falhas+1)); fi }

echo "== checks (colar-checks)"
# Build quebrado reprova aqui: sem isso o binário antigo rodaria e "passaria".
swift build --product colar-checks > /tmp/colar-build-checks.log 2>&1
check "colar-checks compila" "[ $? -eq 0 ]" || grep -E "error" /tmp/colar-build-checks.log
.build/debug/colar-checks
check "colar-checks passou" "[ $? -eq 0 ]"

echo "== bundle"
scripts/bundle.sh release > /tmp/colar-bundle.log 2>&1
check "bundle montado" "[ $? -eq 0 ] && [ -x build.noindex/Colar.app/Contents/MacOS/Colar ]"
[ -n "${COLAR_ADHOC:-}" ] || check "assinado com Apple Development (não ad hoc)" "codesign -dvv build.noindex/Colar.app 2>&1 | grep -q 'Authority=Apple Development'"
[ -n "${COLAR_ADHOC:-}" ] || check "requisito do TCC usa o certificado, não o hash" "codesign -d -r- build.noindex/Colar.app 2>&1 | grep -q 'certificate leaf'"
check "bundle id app.colar" "[ \"\$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' build.noindex/Colar.app/Contents/Info.plist)\" = app.colar ]"
check "ícone no bundle (Colar.icns com 1024)" "[ -f build.noindex/Colar.app/Contents/Resources/Colar.icns ] && iconutil -c iconset build.noindex/Colar.app/Contents/Resources/Colar.icns -o /tmp/colar-icone-teste.iconset && [ -f /tmp/colar-icone-teste.iconset/icon_512x512@2x.png ]"
check "esquema colar:// no Info.plist" "/usr/libexec/PlistBuddy -c 'Print CFBundleURLTypes:0:CFBundleURLSchemes:0' build.noindex/Colar.app/Contents/Info.plist | grep -qx colar"
check "sons no bundle (copiar.wav e colar.wav)" "[ -f build.noindex/Colar.app/Contents/Resources/copiar.wav ] && [ -f build.noindex/Colar.app/Contents/Resources/colar.wav ]"
check "nenhum som de alerta do sistema no código" "! grep -rqE 'NSSound\\(named' Sources/"
check "binário sem o caminho da máquina (/Users/...)" "! strings -a build.noindex/Colar.app/Contents/MacOS/Colar | grep -q '/Users/'"
check "sem Dock (LSUIElement)" "/usr/libexec/PlistBuddy -c 'Print LSUIElement' build.noindex/Colar.app/Contents/Info.plist | grep -q true"

check "inicia com o Mac (SMAppService.mainApp)" "grep -q 'SMAppService.mainApp' Sources/Colar/main.swift"
check "cópia de build fora do Spotlight (.noindex)" "! grep -q 'APP=\"build/' scripts/bundle.sh"

echo "\n$((total-falhas))/$total ok"
[ $falhas -eq 0 ]
