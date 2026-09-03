# please-bump

A GitHub Action that fails a pull request when it does not bump the
software's version — for R, Python, C++, and anything else, in a single
project or a monorepo of several.

- Compares the PR's base branch against its head, per **group** of files.
- Versions are pulled out with a **regex**, a built-in **preset**, or an
  escape-hatch **command**.
- A group can require **several files to bump together**, and can require
  them to agree — catches "I bumped `DESCRIPTION` but forgot `NEWS.md`", or
  "the header says `1.3.0` but `CMakeLists.txt` still says `1.2.0`".
- A monorepo group only has to bump when its own **paths** were touched.
- Always posts (and keeps up to date) one **sticky PR comment** reporting
  what moved, from what to what, and what kind of bump it was.

## Quick start

```yaml
# .github/workflows/please-bump.yml
name: please-bump
on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

jobs:
  please-bump:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # please-bump needs the base branch's history
      - uses: gvegayon/please-bump@v1
```

Then add `.github/please-bump.yaml` — see
[please-bump.example.yaml](please-bump.example.yaml) for a full tour, or the
minimal version below:

```yaml
version: 1
groups:
  my-package:
    files: [DESCRIPTION]
    preset: r-package
```

`fetch-depth: 0` is the simplest way to guarantee the base commit is
reachable. If you'd rather keep a shallow checkout, please-bump will try
`git fetch --no-tags --depth=1 origin <base-branch>` itself before running.

## Inputs

| input | default | purpose |
|---|---|---|
| `config` | `.github/please-bump.yaml` | Path to the config file. |
| `comment` | `true` | Post/update the sticky PR comment (pass or fail). |
| `comment-title` | `Version bump check` | Heading for the comment and step summary. |
| `gh-token` | `${{ github.token }}` | Token for reading/posting the comment. Needs `pull-requests: write`. |
| `fail-on-error` | `true` | `false` = report only, never fail the job. A broken config still always fails. |
| `base-ref` | the PR's base SHA | Override the ref to compare against. |
| `head-ref` | `HEAD` | Override the ref to compare. |
| `working-directory` | `.` | Run from a subdirectory (e.g. a monorepo checked out elsewhere). |

## Outputs

| output | meaning |
|---|---|
| `result` | `pass` or `fail`. |
| `versions` | JSON: `{ "<group>": {base_version, head_version, bump, status}, ... }`. |
| `report` | Path to the rendered Markdown report. |
| `json` | Path to the full JSON result. |

## Permissions and fork PRs

The sticky comment needs `pull-requests: write`. A PR from a fork gets a
read-only `GITHUB_TOKEN` by default, so posting the comment will fail on
those — please-bump logs a warning and continues; the pass/fail result and
step summary are unaffected either way.

## Config reference

```yaml
version: 1

defaults:              # applied to every group unless overridden
  scheme: semver        # semver | pep440 | r | numeric
  consistency: identical # identical | same-bump | none
  when: changed          # changed | always
  on-missing: skip        # configured file absent:        skip  | error
  on-no-match: error      # file present, nothing matched:  error | skip
  on-empty-group: error   # every file in the group absent: error | warn | skip

types: { ... }          # your own presets — see "Writing your own type"

groups:
  <name>:
    paths: |             # optional. Which changes make this group "touched".
      some/dir/           # a trailing "/" is a directory prefix
      !some/dir/vendor/   # "!" excludes
    when: changed | always
    consistency: identical | same-bump | none
    scheme: ...
    on-missing: ...
    on-no-match: ...
    on-empty-group: ...

    # --- exactly one of the following four shapes ---
    files: [a, b]; regex: ['(...)', '(...)']   # positional, or one regex to broadcast
    files: [a]; parts: {...}; assemble: "..."  # direct parts/assemble
    files: [a]; preset: some-preset            # a preset/type supplies parts/assemble
    rules: [ {preset: x, files: [...]}, {files: [...], parts: {...}} ]  # mixed
```

### `paths`

Governs whether a group counts as "touched" by this PR (`when: changed`,
the default). If you don't set `paths` at all, please-bump falls back to
"did any of this group's own configured files change" — the sensible
default for a single-project repo. In a monorepo, set `paths` explicitly so
an unrelated change elsewhere in the sub-project (not just the version file
itself) still requires a bump.

### `consistency`

- **`identical`** (default) — every file in the group must show the exact
  same version string, on both base and head. Catches "A bumped, B didn't"
  and "A and B bumped to different versions".
- **`same-bump`** — files may carry different version strings (useful when
  mixing schemes), but each must classify to the *same kind* of bump (e.g.
  all "minor").
- **`none`** — each file just has to individually show a real increase; no
  cross-file agreement required.

### Missing files are expected, not failures

Not every R package has a `NEWS.md`; not every Python project has a
`_version.py`. By default (`on-missing: skip`), a configured file that
doesn't exist is simply left out — the remaining files decide the check —
and it's still named in the PR comment so a silently-skipped file never
looks like a passing one. Set `on-missing: error` for a group where every
listed file really must exist.

If **every** file in a group is missing, that's `on-empty-group` (default
`error`) — nothing could be verified, so the check can't pass silently.

### `regex` dialect

POSIX extended regular expressions (ERE), the same dialect as `sed -E`. Use
POSIX character classes — **`[[:space:]]`, `[[:alpha:]]`, `[[:digit:]]`** —
not PCRE shorthand like `\s`, `\d`, `\w`: those aren't portable ERE and will
silently fail to match the way you expect on some platforms. Each `parts`
entry must have exactly one capturing group.

## Built-in presets

| preset | scheme | matches |
|---|---|---|
| `r-package` | `r` | `DESCRIPTION`: `Version: 1.2.3` |
| `r-news` | `r` | `NEWS.md` heading `# 1.2.3` (see the preset file for the exact convention it expects) |
| `python-pyproject` | `pep440` | `pyproject.toml`: `version = "1.2.3"` |
| `python-setupcfg` | `pep440` | `setup.cfg`: `version = 1.2.3` |
| `python-dunder` | `pep440` | `__version__ = "1.2.3"` — needs an explicit `files:` |
| `cpp-semantic` | `numeric` | `#define ..._VERSION_MAJOR/MINOR/PATCH ...`, assembled |
| `cmake-project` | `numeric` | `CMakeLists.txt`: `project(name VERSION 1.2.3 ...)` |
| `node-package` | `semver` | `package.json`: `"version": "1.2.3"` |
| `cargo` | `semver` | `Cargo.toml`: `version = "1.2.3"` |

See [presets/](presets/) for the exact regex each one uses.

## Version schemes

| scheme | covers | classification labels |
|---|---|---|
| `semver` | SemVer 2.0.0, full precedence | `major`, `minor`, `patch`, `prerelease`, `release`, `build-only`, `downgrade`, `unchanged` |
| `pep440` | Python (epoch, pre/post/dev; documented subset — see [src/schemes/pep440.sh](src/schemes/pep440.sh)) | `epoch`, `major`, `minor`, `patch`, `prerelease`, `post`, `dev`, `release`, `build-only`, `downgrade`, `unchanged` |
| `r` | `1.2.3`, `1.2-3`, and the `.9000`-style devel suffix | `major`, `minor`, `patch`, `devel`, `downgrade`, `unchanged` |
| `numeric` | Any `N(.N)*` version — CalVer, C++ triples, etc. Labels components via `part-labels`. | `<label>` or `component-N`, `downgrade`, `unchanged` |

A label outside `{downgrade, unchanged, build-only, invalid-*}` counts as a
real bump.

## Writing your own type

A `types:` entry (or a preset file) has this shape:

```yaml
scheme: semver              # semver | pep440 | r | numeric
files: ["some/default/path"] # optional default files, overridable per group
part-labels: [major, minor, patch]  # only meaningful for scheme: numeric
parts:
  version: '^Version:[[:space:]]*(.+)$'
assemble: "{version}"       # optional if there's exactly one part
command: null                # or: a shell command printing the version to stdout
```

The single-regex `files:`/`regex:` group shorthand is sugar for exactly
this shape with one part named `version`. The C++ preset shows the general
case: several named `parts`, each with its own one-capture-group regex,
combined by `assemble` — this is how a version split across several
`#define`s (or several files) becomes one comparable string.

## How it works, and how it's tested

please-bump is pure bash + `jq` + `yq` (all preinstalled on GitHub-hosted
Ubuntu and macOS runners) — no language runtime to install. It's also
written to run on bash 3.2 (macOS's stock `/bin/bash`), so it behaves
identically in local testing and in CI on either OS.

```bash
tests/run-tests.sh            # everything
tests/run-tests.sh unit       # unit tests only
tests/run-tests.sh integration # integration tests only (real throwaway git repos)
```

See [src/](src/) for the implementation and [presets/](presets/) for the
built-in preset definitions.

## License

[MIT](LICENSE)
