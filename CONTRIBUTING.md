# Contributing

Thanks for considering a contribution. This document covers building from
source, the patch workflow, and the bits of style we care about.

## Build

Build deps (Arch names; see `packaging/*` for other distros):

```
plasma-workspace plasma-activities plasma-activities-stats
kservice ki18n kiconthemes kcoreaddons kwindowsystem kio krunner
libplasma kpackage qt6-base qt6-declarative layer-shell-qt
appstream-qt extra-cmake-modules cmake gettext
```

Configure + build the plasmoid:

```sh
cmake --preset release      # see CMakePresets.json for other presets
cmake --build build
```

Install to `~/.local/share/plasma/plasmoids/` (for dev iteration without
touching system paths) via `makepkg -si` from the bundled `PKGBUILD`, or
`cmake --install build --prefix ~/.local`. Then in Plasma:
*Add Widgets → AppGrid*.

## Run the tests

```sh
cmake --preset tests
cmake --build build-tests
QT_QPA_PLATFORM=offscreen ctest --test-dir build-tests
```

Tests cover the C++ models (search ranking, filter, sort, runner filter,
unified search, plugin helpers, …) and a QtQuickTest harness for the QML
controllers under `tests/qml/`. New behaviour should land with coverage.

## Style

- C++: `clang-format -i` and `clang-tidy` are enforced by CI; the
  config files live at the repo root. Running `clang-format -i
  src/<file>` before pushing saves a CI round-trip.
- QML: `qmllint -I /usr/lib/qt6/qml package/contents/ui/<file>.qml`.
  The config sits at `.qmllint.ini`.
- Comments: try to explain the *why* — the hidden constraint, the bug
  fix, the invariant — and skip restating *what* the code already
  says. Short over long; multi-paragraph docstrings on internal
  helpers usually aren't pulling their weight.
- Identifiers: descriptive names work best; underscores are reserved
  for private state-flag properties (`_snapHeight`, `_gridRevealed`).
- KDE-flavoured idioms: prefer Kirigami / PlasmaComponents over raw
  Qt Quick Controls where a themed equivalent exists, and try to use
  `Kirigami.Units` for sizing and spacing so the launcher scales with
  the user's theme.

## Commit messages

Conventional-Commits style — the CI changelog generator (`git-cliff`) groups
by type:

```
<type>(<scope>): <subject>

<body — wrap at 72 cols, explain the why>
```

Common types: `feat`, `fix`, `refactor`, `perf`, `docs`, `chore`,
`build`, `ci`, `polish`, `test`. Scope is the affected module (e.g.
`search`, `config`, `ui`, `packaging`). Issue references in the
subject (`fix(search): … (#151)`) when applicable.

## Pull requests

- Fork → branch → push → PR against `main` (stable bugs against
  `maintenance/<series>`).
- Try to keep PRs focused; unrelated cleanups tend to land more
  smoothly in their own PR.
- CI gates the merge: clang-format, clang-tidy, codespell, qmllint,
  cppcheck, tests. Failures block — fix locally before pushing.
- User-facing strings should be wrapped in
  `i18nd("dev.xarbit.appgrid", …)` (or `i18ndc(...)` with a
  translator context).
- Pre-built packages, screenshots, and local-only notes are already
  gitignored (`*.pkg.tar.zst`, `notes/`, `result/`, …) — please keep
  it that way.

## Reporting bugs / requesting features

Please use the issue templates under
[`.github/ISSUE_TEMPLATE/`](.github/ISSUE_TEMPLATE/). They prompt for
the things triage almost always needs — AppGrid version (Settings →
`i:` view), Plasma version, distro, install method, and reproducer
steps. Triage labels follow `bug`, `enhancement`, `upstream-limitation`,
`regression`, `needs-info`.

## AI-assisted code

AI-assisted contributions are welcome — any assistant, commercial,
open, or local. AI is here, and it isn't going anywhere.

To be straight about it: I work in the field and use AI at work and
on personal projects. I don't fully trust the output, and I'd suggest
you don't either. It's a tool — a very helpful one — and like any
tool it can be used well or poorly. Just be honest about where it
helped.

We don't vibe-code here — the usual software-engineering practices
still apply. The bar for an AI-assisted patch is the same as for any
other patch:

- **Understand it.** If you can't walk a reviewer through why each
  non-trivial line is there, please take another pass before sending
  it. "The model wrote it" isn't enough on its own.
- **See it through.** Finish what you start — loose ends are easy
  to miss in a review. When you decouple, finish the pattern across
  the boundary files; when you rename, rename everywhere; when you
  refactor or remove, sweep for dead code (unused includes, orphan
  helpers, comments referring to what you just deleted).
- **Test it.** New behaviour should ship with coverage. CI runs
  clang-format, clang-tidy, codespell, cppcheck, qmllint, ctest and
  the QtQuickTest harness — running the same set locally saves a
  CI round-trip:
  ```sh
  cmake --preset ci && cmake --build --preset ci
  # clang-tidy: strip the gcc-only flag clang doesn't grok, then run
  sed -i 's/-mno-direct-extern-access//g' build-ci/compile_commands.json
  run-clang-tidy -p build-ci -quiet -warnings-as-errors='*' 'src/.*\.cpp'
  ctest --preset ci
  ```
- **Follow the style above.** KDE idioms, comments that explain the
  *why* and stay current, named properties over magic numbers, no
  dead or stale code.
- **Skim the diff before sending it.** Models sometimes invent APIs,
  leave debug prints, fold in unrelated edits, or quietly tweak code
  you didn't intend to change. Easier to catch yourself than in a
  review.

Tools are great when they help. Either way, the patch carries your
name. As the project grows we're trying to keep the codebase coherent
and the patterns clean — your care helps a lot.

## License

By contributing you agree your changes are licensed under GPL-2.0-or-later,
matching the project license.
