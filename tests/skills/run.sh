#!/usr/bin/env bash
# Frontmatter checks for every SKILL.md, using a strict YAML parser (Ruby Psych).
# Claude Code's parser tolerates some invalid YAML (e.g. an unquoted ": " inside a
# description); pi and other harnesses that read the skill-sync copies do not.
# Usage: tests/skills/run.sh
set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plugins/elixir-plus/skills" && pwd)"
pass=0; fail=0

for skill in "$SKILLS"/*/SKILL.md; do
  dir=$(basename "$(dirname "$skill")")
  if out=$(ruby -ryaml -e '
      text = File.read(ARGV[0])
      m = text.match(/\A---\n(.*?)\n---\n/m) or abort "no frontmatter block"
      root = Psych.parse(m[1]).root
      keys = root.is_a?(Psych::Nodes::Mapping) ? root.children.each_slice(2).map { |k, _| k.value } : []
      dup = keys.find { |k| keys.count(k) > 1 }
      abort "duplicate key #{dup.inspect}" if dup
      fm = YAML.safe_load(m[1])
      abort "frontmatter is not a mapping" unless fm.is_a?(Hash)
      abort "name #{fm["name"].inspect} != directory #{ARGV[1]}" unless fm["name"] == ARGV[1]
      d = fm["description"]
      abort "description missing or not a string" unless d.is_a?(String) && !d.strip.empty?
    ' "$skill" "$dir" 2>&1); then
    pass=$((pass + 1)); printf '  ok   %s\n' "$dir"
  else
    fail=$((fail + 1)); printf '  FAIL %s\n     %s\n' "$dir" "$(printf %s "$out" | head -1)"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
