setup() { load test_helper; cd "$REPO_ROOT"; export GROUNDCREW_NO_COLOR=1; }

@test "catalog has graphify and vault defaulting on" {
  run bash -c 'source lib/catalog.sh; catalog::items'
  [[ "$output" == *"graphify|"* ]]
  echo "$output" | grep '^graphify|' | grep -q 'on$'
  echo "$output" | grep '^vault|'    | grep -q 'on$'
}

@test "recommended preset selects the on-by-default items" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::preset recommended'
  [[ "$output" == *"graphify"* ]]
  [[ "$output" == *"vault"* ]]
  [[ "$output" != *"docker"* ]]
}

@test "everything preset selects all ids" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::preset everything'
  for id in graphify vault rembg media playwright docker; do
    [[ "$output" == *"$id"* ]]
  done
}

@test "minimal preset selects nothing" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::preset minimal'
  [ -z "$output" ]
}

@test "unknown preset exits 2" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::preset bogus'
  [ "$status" -eq 2 ]
}

@test "describe renders what and why for an id" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::describe graphify'
  [[ "$output" == *"knowledge graph"* ]]
  [[ "$output" == *"Why"* || "$output" == *"·"* ]]
}

@test "tiers lists all four competency levels" {
  run bash -c 'source lib/catalog.sh; catalog::tiers'
  [[ "$output" == *"terminal-first|"* ]]
  [[ "$output" == *"new|"* ]]
  [[ "$output" == *"some|"* ]]
  [[ "$output" == *"experienced|"* ]]
}

@test "competency_default maps beginner tiers to recommended" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::competency_default new'
  [ "$output" = "recommended" ]
}

@test "competency_default maps experienced to everything" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::competency_default experienced'
  [ "$output" = "everything" ]
}

@test "verbosity is verbose for absolute beginner, terse for experienced" {
  v1=$(bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::verbosity terminal-first')
  v2=$(bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::verbosity experienced')
  [ "$v1" = "verbose" ]
  [ "$v2" = "terse" ]
}

@test "unknown tier exits 4" {
  run bash -c 'source lib/catalog.sh; source lib/picker.sh; picker::competency_default bogus'
  [ "$status" -eq 4 ]
}
