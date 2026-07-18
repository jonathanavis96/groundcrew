# shellcheck shell=bash
# Groundcrew logging. All output goes to stderr so stdout stays clean for data.
if [[ -t 2 && -z "${GROUNDCREW_NO_COLOR:-}" ]]; then
  _gc_c_reset=$'\e[0m'; _gc_c_blue=$'\e[34m'; _gc_c_yellow=$'\e[33m'
  _gc_c_red=$'\e[31m'; _gc_c_green=$'\e[32m'; _gc_c_bold=$'\e[1m'
else
  _gc_c_reset=; _gc_c_blue=; _gc_c_yellow=; _gc_c_red=; _gc_c_green=; _gc_c_bold=
fi
log::info()  { printf '%s\n' "${_gc_c_blue}·${_gc_c_reset} $*" >&2; }
log::step()  { printf '%s\n' "${_gc_c_bold}▸ $*${_gc_c_reset}" >&2; }
log::ok()    { printf '%s\n' "${_gc_c_green}✓${_gc_c_reset} $*" >&2; }
log::warn()  { printf '%s\n' "${_gc_c_yellow}!${_gc_c_reset} $*" >&2; }
log::error() { printf '%s\n' "${_gc_c_red}✗${_gc_c_reset} $*" >&2; }
