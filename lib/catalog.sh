# shellcheck shell=bash
# id|title|what|why|cost|default
catalog::items() {
  cat <<'EOF'
graphify|Graphify|Turns your codebase into a queryable knowledge graph|Your agent finds the right files fast instead of grepping blindly|~1 min, small|on
vault|Obsidian + starter vault|A local notes app wired into your agent|Gives the agent persistent memory across sessions|~2 min, small|on
rembg|rembg|Background removal for images|One-command cutouts; downloads an ML model|~3 min, ~200MB model|off
media|Media tools|ffmpeg + ImageMagick|Convert/resize/transcode images and video|~2 min, medium|off
playwright|Playwright + Chromium|Headless browser automation|Let your agent drive a real browser|~3 min, ~300MB|off
docker|Docker|Container runtime in WSL|Run containerised apps and databases|~4 min, large|off
EOF
}

# id|label — the 4 competency tiers asked first (drives verbosity + default preset)
catalog::tiers() {
  cat <<'EOF'
terminal-first|Never used a terminal
new|New to this
some|Some experience
experienced|Experienced
EOF
}
