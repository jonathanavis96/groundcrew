# shellcheck shell=bash
media::install() {
  guard::run_once optional-media _media__do
}
_media__do() {
  log::step "Installing media tools"
  _media__install_ffmpeg || return 1
  _media__install_rembg || return 1
  log::ok "media tools installed"
}
_media__install_ffmpeg() {
  case "$(os::detect)" in
    linux)
      sudo apt-get update -y || return 1
      sudo apt-get install -y ffmpeg || return 1
      ;;
    macos)
      brew install ffmpeg || return 1
      ;;
    *)
      log::error "unsupported OS for ffmpeg install"
      return 1
      ;;
  esac
}
# rembg as an isolated tool, preferring uv (installed by core/python.sh) with a
# pipx fallback for hosts that skipped that core step. Plain "rembg" ships no
# inference backend and fails at first use, not at install — the [cpu] extra
# pulls the ONNX CPU runtime. Quoted: [cpu] contains glob characters the shell
# would otherwise try to expand.
_media__install_rembg() {
  if guard::has_cmd uv; then
    uv tool install 'rembg[cpu]' || return 1
  elif guard::has_cmd pipx; then
    pipx install 'rembg[cpu]' || return 1
  else
    log::error "neither uv nor pipx found — cannot install rembg"
    return 1
  fi
}
