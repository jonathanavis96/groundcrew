# shellcheck shell=bash
docker::install() {
  guard::run_once optional-docker _docker__do
}
_docker__do() {
  log::step "Installing Docker"
  case "$(os::detect)" in
    linux)
      # USER is a login-shell variable: unset under cron, `env -i` or some
      # container shells, where install.sh's `set -u` would abort on it.
      local user="${USER:-$(id -un)}"
      sudo apt-get update -y || return 1
      sudo apt-get install -y docker.io || return 1
      sudo usermod -aG docker "$user" || return 1
      log::warn "added $user to the docker group — log out and back in (or run: newgrp docker) before using docker without sudo"
      ;;
    macos)
      brew install --cask docker || return 1
      log::warn "Docker Desktop installed — it's a GUI app: launch it once from Applications to finish setup, and review Docker's licensing terms for your use case"
      ;;
    *)
      log::error "unsupported OS for docker install"
      return 1
      ;;
  esac
  log::ok "docker installed"
}
