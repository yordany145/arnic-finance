#!/usr/bin/env bash
# Publica una versión: compila el APK firmado, calcula su SHA-256 y lo sube como
# Release de GitHub junto con latest.json, que es lo que lee "Buscar actualización".
#
# Uso:  scripts/release.sh "Notas de la versión"
# Antes: subir `version:` en pubspec.yaml (el número tras el + SIEMPRE debe crecer).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/flutter/bin:$PATH" ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"

repo=yordany145/arnic-finance
notes="${1:-}"
version=$(sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)$/\1/p' pubspec.yaml)
build=$(sed -n 's/^version: \([0-9.]*\)+\([0-9]*\)$/\2/p' pubspec.yaml)
[ -n "$version" ] && [ -n "$build" ] || { echo "No pude leer version: de pubspec.yaml" >&2; exit 1; }
[ -e android/key.properties ] || { echo "Falta android/key.properties: sin la clave propia el APK no se podría actualizar encima." >&2; exit 1; }
tag="v$version"
if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then echo "El release $tag ya existe: sube la versión en pubspec.yaml." >&2; exit 1; fi
if [ -n "$(git status --porcelain)" ]; then echo "Hay cambios sin commit: haz commit y push antes de publicar." >&2; exit 1; fi

flutter build apk --release --target-platform android-arm64
out=build/release; rm -rf "$out"; mkdir -p "$out"
cp build/app/outputs/flutter-apk/app-release.apk "$out/arnic-finance.apk"
hash=$(sha256sum "$out/arnic-finance.apk" | cut -d' ' -f1)
python3 - "$out/latest.json" "$version" "$build" "$hash" "$repo" "$tag" "$notes" <<'PY'
import json, sys
path, version, build, sha, repo, tag, notes = sys.argv[1:8]
json.dump({"versionName": version, "buildNumber": int(build), "sha256": sha, "notes": notes,
           "apkUrl": f"https://github.com/{repo}/releases/download/{tag}/arnic-finance.apk"}, open(path, "w"), ensure_ascii=False, indent=2)
PY
gh release create "$tag" "$out/arnic-finance.apk" "$out/latest.json" --repo "$repo" --title "Arnic Finance $version" --notes "${notes:-Versión $version}" --latest
echo "Publicado $tag (build $build, sha256 $hash)"
