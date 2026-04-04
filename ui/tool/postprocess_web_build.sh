#!/usr/bin/env bash
set -euo pipefail

build_dir="${1:?build dir required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ui_dir="$(cd "${script_dir}/.." && pwd)"
target_worker="${build_dir}/flutter_service_worker.js"
fragment="${ui_dir}/web/push_service_worker_fragment.js"
temp_file="${target_worker}.tmp"

if [[ ! -f "${target_worker}" ]]; then
  echo "Missing generated service worker: ${target_worker}" >&2
  exit 1
fi

if grep -q "NARLUN_DEFAULT_NOTIFICATION" "${target_worker}"; then
  exit 0
fi

cat "${target_worker}" "${fragment}" > "${temp_file}"
mv "${temp_file}" "${target_worker}"
