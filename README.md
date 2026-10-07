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
- **Bump once per release, not once per PR**: by default a PR only has to
  bump when the version on its branch has already been released — see
  [Shipping several PRs under one version](#shipping-several-prs-under-one-version).
- Always posts (and keeps up to date) one **sticky PR comment** reporting
  what moved, from what to what, and what kind of bump it was.

## Quick start

```yaml
# .github/workflows/please-bump.yml
name: please-bump
on:
  pull_request:
    # labeled/unlabeled/edited re-run the check when a waiver label or
    # marker is added or removed.
    types: [opened, synchronize, reopened, labeled, unlabeled, edited]

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

## Shipping several PRs under one version

Most teams don't release on every PR: they bump the version once after a
release, keep merging fixes under that unreleased version, and cut a GitHub
release when ready. please-bump follows that by default.

### The default: bump once after each release (`unchanged-policy: release`)

A touched group passes with an **unchanged** version as long as that version
**hasn't been released yet**. Once a GitHub release for it exists, the next
PR that touches the group has to bump. If the project has no release at all
yet, an unchanged version passes.

| main is at | latest GitHub release | PR leaves the version alone | result |
|---|---|---|---|
| `1.2.3` | none yet | yes | ✅ unchanged (no release yet) |
| `1.2.3` | `v1.2.3` | yes | ❌ already released — bump it |
| `1.2.3.9000` | `v1.2.3` | yes | ✅ unchanged (unreleased) |
| `1.2.3.9000` | `v1.2.3` | no, bumps to `1.2.4` | ✅ **patch** update |
| `1.2.2.9000` | `v1.2.3` | either | ❌ behind latest release |

So the day-to-day loop is:

- **R** — release `1.2.3`; the first PR after it bumps to `1.2.3.9000`
  (and adds the `# mypkg (development version)` / `1.2.3.9000` NEWS heading);
  every later PR just adds to it; the release PR bumps to `1.2.4`. Bumping
  `.9001`, `.9002`, … on every PR still works — it's just no longer required.
- **Python** — `1.2.3` → `1.2.4.dev0` after release, then `1.2.4` at release.
- **Node / Rust / C++ / anything else** — bump straight to the next
  version (`1.2.4`, or `1.2.4-dev`) after the release, then release it.

Released versions are read from the **GitHub Releases** of the repository
(drafts excluded, pre-releases included — a published `v1.3.0-rc.1` counts
as released), with their tag names matched against `tag-pattern`:

```yaml
release-source: releases     # releases (default) | tags
defaults:
  tag-pattern: "v?{version}" # default: matches "1.2.3" and "v1.2.3"
groups:
  engine:
    tag-pattern: "engine-v{version}"   # monorepo: per-group tags
```

`{version}` captures the version, `{group}` is the group's name, `?` makes
the previous character optional, and everything else is literal. Only tags
whose captured text is a valid version under the group's scheme count, so
unrelated tags (`nightly`, another group's `other-v2.0.0`) are ignored.
(One caveat for the `r` and `numeric` schemes, where a lone `1` is a valid
version: with `release-source: tags`, a floating major tag like `v1` reads
as version `1`. The default `releases` source is unaffected, since floating
tags normally have no GitHub release of their own.)

If the project only tags (no GitHub releases), set `release-source: tags` to
read local git tags instead; that needs `fetch-depth: 0` on checkout. If
the release list can't be fetched (no token, API error), please-bump falls
back to git tags and says so in the report; a checkout with no tags at all
gets a note pointing at `fetch-depth: 0`, since it usually means a shallow
clone rather than a project with no releases.

> **Known gap.** A PR that passed while main was unreleased can still be
> merged *after* a release is cut, without re-running. Turn on "Require
> branches to be up to date before merging" in branch protection so the
> check re-runs against the new base — or accept that the next PR will
> have to bump instead.

### Alternative: `unchanged-policy: dev`

For projects that don't publish releases or tags: an unchanged version
passes when it is a **development/pre-release version** — R `x.y.z.9000`+,
PEP 440 `.devN` / `aN` / `bN` / `rcN`, SemVer `-anything`. The `numeric`
scheme has no such concept, so `dev` never excuses a `numeric` group.

### Alternative: `unchanged-policy: never`

The strict mode: every PR that touches a group must bump it.

### Why `release` and `dev` aren't combined

`unchanged-policy` takes a single value. With releases available, `release`
already covers everything `dev` would: an unreleased dev version passes,
nothing-released-yet passes — and where they differ, `release` is right
(an unchanged `1.3.0-rc.1` that was published as a pre-release *should*
need `rc.2` or `1.3.0`, which `dev` would let through). Use `dev` only when
there is no release history to consult.

### Per-PR waiver: a label or a marker

Whatever the policy, a PR can waive a "not bumped" / "already released" /
"behind latest release" failure — e.g. a docs-only change inside a
group's `paths`:

- the label **`no-version-bump`**, or
- the marker **`[please-bump skip]`** anywhere in the PR description, or
  **`[please-bump skip: group-a, group-b]`** to waive only those groups.

The group is then reported as ☑️ **waived**, and doesn't fail the check.
A waiver never excuses a downgrade, an unparseable version, files that
disagree, or a missing version file. Labels and the marker are read live
from the PR (so re-running a job sees a label added later); add `labeled`,
`unlabeled` and `edited` to the workflow's `types:` so adding one re-runs
the check right away.

```yaml
waiver:
  labels: [no-version-bump]   # default; [] disables label waivers
  marker: true                # default; false disables the body marker
```

Anyone who can open a PR can write the marker — including authors of fork
PRs — while only users with triage access can add labels. Set
`marker: false` if a waiver should always need a maintainer.

## Inputs

| input | default | purpose |
|---|---|---|
| `config` | `.github/please-bump.yaml` | Path to the config file. |
| `comment` | `true` | Post/update the sticky PR comment (pass or fail). |
| `comment-title` | `Version bump check` | Heading for the comment and step summary. |
| `gh-token` | `${{ github.token }}` | Token for listing releases, reading the PR's labels/description, and posting the comment. Needs `contents: read` and `pull-requests: write`. |
| `fail-on-error` | `true` | `false` = report only, never fail the job. A broken config still always fails. |
| `base-ref` | the PR's base SHA | Override the ref to compare against. |
| `head-ref` | `HEAD` | Override the ref to compare. |
| `working-directory` | `.` | Run from a subdirectory (e.g. a monorepo checked out elsewhere). |

## Outputs

| output | meaning |
|---|---|
| `result` | `pass` or `fail`. |
| `versions` | JSON: `{ "<group>": {base_version, head_version, bump, status, reason}, ... }`. `status` is `pass`, `fail`, `waived`, `skipped` or `warn`; `reason` explains a pass without a bump (`unreleased`, `no-release`, `dev`), a waiver (`label:<name>`, `marker`), or a policy failure (`released`, `behind-release`, `not-bumped`). |
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
  unchanged-policy: release  # when an unchanged version is OK: release | dev | never
  tag-pattern: "v?{version}" # how release tag names map to versions

release-source: releases  # where released versions come from: releases | tags
waiver:                   # per-PR opt-out
  labels: [no-version-bump]
  marker: true

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
    unchanged-policy: ...
    tag-pattern: ...

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
| `r-news-titled` | `r` | `NEWS.md` heading `# mypkg 1.2.3` — what `usethis::use_news_md()` produces |
| `r-news-changes` | `r` | `NEWS.md` heading `# Changes in mypkg version 1.2.3 (2026-07-22)` |
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
real bump. An `unchanged` (or `build-only`) group can still pass under its
`unchanged-policy` — see
[Shipping several PRs under one version](#shipping-several-prs-under-one-version).

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
