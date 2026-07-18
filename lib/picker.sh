# shellcheck shell=bash
picker::preset() {
  case "$1" in
    minimal) : ;;
    recommended) catalog::items | awk -F'|' '$6=="on"{print $1}' ;;
    everything)  catalog::items | awk -F'|' '{print $1}' ;;
    *) log::error "unknown preset: $1"; return 2 ;;
  esac
}

picker::describe() {
  local id="$1" line
  line=$(catalog::items | awk -F'|' -v id="$id" '$1==id{print; found=1} END{exit !found}') || {
    log::error "unknown id: $id"; return 3; }
  awk -F'|' '{printf "%s — %s · Why: %s (%s)\n", $2, $3, $4, $5}' <<<"$line"
}

picker::competency_default() {
  case "$1" in
    terminal-first|new|some) echo recommended ;;
    experienced) echo everything ;;
    *) log::error "unknown tier: $1"; return 4 ;;
  esac
}

picker::verbosity() {
  case "$1" in
    terminal-first|new) echo verbose ;;
    some|experienced) echo terse ;;
    *) log::error "unknown tier: $1"; return 4 ;;
  esac
}
