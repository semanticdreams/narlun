#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ui_dir="$(cd "${script_dir}/.." && pwd)"

cd "${ui_dir}"
flutter build web --release "$@"
"${script_dir}/postprocess_web_build.sh" "${ui_dir}/build/web"
