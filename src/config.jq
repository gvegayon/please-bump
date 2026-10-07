# please-bump config resolver.
#
# Turns the authored YAML config (already converted to JSON) plus the merged
# preset/type catalog into a normalized manifest:
#
#   { release_source, waiver: { labels, marker },
#     groups: { <name>: { when, consistency, on_empty_group,
#                          unchanged_policy, tag_pattern,
#                          paths_include, paths_exclude,
#                          rules: [ { files, parts, assemble, command,
#                                     scheme, part_labels,
#                                     on_missing, on_no_match } ] } } }
#
# Any rule that could not be resolved carries an "_error" key instead of the
# normal fields (a group-level problem puts "_error" on the group itself);
# config.sh scans the whole manifest for these afterward and aborts with all
# of them listed, rather than failing on the first one.

def trim: gsub("^\\s+|\\s+$"; "");

def path_lines($v):
  if $v == null then []
  elif ($v | type) == "array" then $v
  else ($v | split("\n") | map(trim) | map(select(length > 0)))
  end;

def split_paths($v):
  path_lines($v) as $lines
  | {
      include: [ $lines[] | select(startswith("!") | not) ],
      exclude: [ $lines[] | select(startswith("!")) | .[1:] ]
    };

# First non-null value of $obj[$k] across $keys, checked in order.
def dget($obj; $keys):
  reduce $keys[] as $k (null; if . == null then ($obj[$k] // null) else . end);

def resolve_rule($g; $defaults; $types; $raw):
  ($raw.preset // null) as $preset_name
  | (
      if $preset_name != null then
        if ($types | has($preset_name)) then $types[$preset_name]
        else {"_error": "unknown preset/type '\($preset_name)'"}
        end
      else {}
      end
    ) as $preset
  | ($preset + ($raw | del(.preset))) as $merged
  | if ($merged | has("_error")) then
      {"_error": $merged["_error"]}
    else
      ($merged.files // []) as $files
      | ($merged.parts // {}) as $parts
      | (
          if $merged.assemble != null then $merged.assemble
          elif ($parts | length) == 1 then "{" + ($parts | keys[0]) + "}"
          else null
          end
        ) as $assemble
      | if ($files | length) == 0 then
          {"_error": "rule has no 'files'"}
        elif ($parts | length) == 0 and ($merged.command == null) then
          {"_error": "rule has neither 'parts'/'regex' nor 'command' to extract a version"}
        elif $assemble == null then
          {"_error": "rule has multiple 'parts' but no 'assemble' template"}
        else
          {
            files: $files,
            parts: $parts,
            assemble: $assemble,
            command: ($merged.command // null),
            scheme: (dget($merged; ["scheme"]) // dget($g; ["scheme"]) // $defaults.scheme // "semver"),
            part_labels: ($merged["part-labels"] // dget($g; ["part-labels"]) // null),
            on_missing: (dget($merged; ["on-missing"]) // dget($g; ["on-missing"]) // $defaults["on-missing"] // "skip"),
            on_no_match: (dget($merged; ["on-no-match"]) // dget($g; ["on-no-match"]) // $defaults["on-no-match"] // "error")
          }
        end
    end;

def raw_rules($g):
  if ($g.rules // null) != null then
    $g.rules
  elif ($g.preset // null) != null then
    [ $g | del(.paths, .consistency, .when, .["on-empty-group"], .["unchanged-policy"], .["tag-pattern"]) ]
  elif ($g.files // null) != null and ($g.regex // null) != null then
    ($g.files) as $files
    | ($g.regex) as $regexes
    | (
        if ($regexes | length) == 1 then
          [ { files: $files, parts: {version: $regexes[0]} } ]
        elif ($regexes | length) == ($files | length) then
          [ range(0; $files | length) as $i | { files: [$files[$i]], parts: {version: $regexes[$i]} } ]
        else
          [ {"_error": "group has \($files|length) files but \($regexes|length) regexes (must match 1:1, or supply exactly one regex to broadcast to every file)"} ]
        end
      )
  elif ($g.files // null) != null and ($g.parts // null) != null then
    [ { files: $g.files, parts: $g.parts, assemble: ($g.assemble // null), command: ($g.command // null) } ]
  else
    [ {"_error": "group has none of: 'rules', 'preset', 'files'+'regex', 'files'+'parts'"} ]
  end;

def resolve_group($g; $defaults; $types):
  (raw_rules($g) | map(resolve_rule($g; $defaults; $types; .))) as $rules
  | (split_paths($g.paths)) as $paths
  # When a group has no explicit `paths:`, "did this group change?" falls
  # back to "did any of its own configured version files change" — the
  # sensible default for a single-project repo, where nobody should have to
  # spell out `paths` just to get `when: changed` to work.
  | (
      if ($g.paths // null) == null then
        ($rules | map(.files? // []) | flatten | unique)
      else
        $paths.include
      end
    ) as $effective_include
  | (dget($g; ["unchanged-policy"]) // $defaults["unchanged-policy"] // "release") as $policy
  | {
      when: (dget($g; ["when"]) // $defaults.when // "changed"),
      consistency: (dget($g; ["consistency"]) // $defaults.consistency // "identical"),
      on_empty_group: (dget($g; ["on-empty-group"]) // $defaults["on-empty-group"] // "error"),
      unchanged_policy: $policy,
      tag_pattern: (dget($g; ["tag-pattern"]) // $defaults["tag-pattern"] // "v?{version}"),
      paths_include: $effective_include,
      paths_exclude: $paths.exclude,
      rules: $rules
    }
  | if (["release", "dev", "never"] | index($policy)) == null then
      . + {"_error": "unknown unchanged-policy '\($policy)' (expected release, dev, or never)"}
    else . end;

. as $root
| ($root.defaults // {}) as $defaults
| ($root.types // {}) as $types
| ($root.groups // {}) as $groups
| ($root.waiver // {}) as $waiver
| {
    release_source: ($root["release-source"] // "releases"),
    waiver: {
      labels: (if $waiver | has("labels") then ($waiver.labels // []) else ["no-version-bump"] end),
      marker: (if $waiver | has("marker") then ($waiver.marker == true) else true end)
    },
    groups: ( $groups | with_entries(.value = resolve_group(.value; $defaults; $types)) )
  }
