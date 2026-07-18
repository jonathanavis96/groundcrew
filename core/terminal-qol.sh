# shellcheck shell=bash
# ripgrep/fd/fzf/bat are provided by base::install on Ubuntu. This module
# exists as an explicit hook point if a future distro needs separate handling.
terminal-qol::note() { log::info "terminal QoL tools come from the base module"; }
