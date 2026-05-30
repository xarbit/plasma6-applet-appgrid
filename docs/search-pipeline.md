# Search pipeline

How AppGrid turns a string in the search bar into the ranked list the user
sees. Reflects the code in `src/appfiltermodel.cpp`, `src/runnerfiltermodel.cpp`,
`src/unifiedsearchmodel.cpp`, and `src/frecencyprovider.cpp`.

## Layers at a glance

```
       search bar text
              │
              ▼
   ┌──────────────────────┐         ┌──────────────────────┐
   │   AppFilterModel     │         │  RunnerFilterModel   │
   │  (apps, in-process)  │         │  (KF6::Runner,       │
   │  filter + rank       │         │   in-process plugins)│
   └──────────┬───────────┘         └──────────┬───────────┘
              └────────────┬───────────────────┘
                           ▼
                ┌──────────────────────┐
                │  UnifiedSearchModel  │
                │  concatenate, expose │
                │  to QML SearchResults │
                └──────────────────────┘
```

`AppFilterModel` runs against the local `.desktop` index (`AppModel`).
`RunnerFilterModel` wraps `KRunner::ResultsModel` for non-app hits
(calculator, unit conversion, file search, web shortcuts, …) and drops any
runner result whose `URL` already appears in the app list.
`UnifiedSearchModel` is a thin concatenator — it does not re-rank.

## Design goal

When you open the launcher, you probably want to launch an app. The pipeline is
tuned for that single objective: type as few characters as possible, see
the app you mean at the top, hit Enter. Everything below — tier ordering,
word-boundary discrimination, the inviolate endpoints, the optional
frecency tiebreak — exists to put the right app on top with the shortest
possible input.

## Federate, not replicate

App search is the part AppGrid owns end-to-end — local in-process matching
against the `AppModel` cache with the tiered ranking described below. For
everything KRunner already does well (calculator, unit conversion, file
search, bookmarks, web shortcuts, …) we federate: KRunner stays sovereign
over its own results, and `UnifiedSearchModel` concatenates them below the
app block (with duplicates filtered).

The split is intentional. Replicating KRunner's runner ecosystem in-process
would mean reimplementing dozens of plugins and tracking upstream forever.
Routing app queries through `KRunner::ResultsModel` instead would give up
the per-keystroke responsiveness — our `QSortFilterProxyModel` over the
pre-folded haystack re-evaluates in a tight loop, while KRunner's
`RunnerManager` debounces and fans queries out across multiple async runner
plugins before re-ranking — and the app-specific heuristics this document
covers (tiered relevance, word-boundary discrimination, mime-default boost,
inviolate tier endpoints).

KActivities is treated the same way. We do not maintain our own usage
database alongside the system one — instead AppGrid broadcasts every launch
via `KActivities::ResourceInstance::notifyAccessed` (so Kickoff / KRunner /
others see AppGrid as a contributing launcher), and the opt-in search
frecency tiebreak reads back the system-wide ranking through
`KActivities::Stats::ResultModel`. One source of truth, shared with every
other Plasma launcher.

## AppFilterModel — filter step

`filterAcceptsRow` uses a pre-folded haystack per row:

```
"name\ngeneric\nkw1\nkw2\n…\nsource"
```

The whole haystack is `toCaseFolded()` once, then a single `contains()`
against the lower-cased query decides membership. This replaces four
case-insensitive `contains()` calls and is the reason rows that match
*anywhere* (name, generic name, any keyword, install source) appear in the
result set even when they will end up at the bottom of the ranking.

## AppFilterModel — relevance ranking

`searchRelevance(idx, query)` assigns each row to one tier (lower number =
better). The tiers, in order:

| Tier | Where                                          | Example: query `ter`            |
|------|------------------------------------------------|----------------------------------|
| 0    | name starts with query                         | **Ter**minal                    |
| 1    | word-boundary substring in name                | VLC Media **Player** for "media" |
| 2    | word-boundary substring in generic name (or in `Comment` if `GenericName` is empty) | **Terminal** Emulator |
| 3    | keyword contains query                         | `terminal` keyword on Ghostty   |
| 4    | mid-word substring in name (deep fallback)     | ghostwri**ter**, boos**ter**    |
| 5    | no match (filtered out)                        | —                                |

"Word boundary" = position 0, or just after a non-alphanumeric character
(`containsAtWordBoundary`). This is what stops a query like `ter` from
ranking `ghostwriter` and `Foreground Booster` above the real terminal
emulators.

### Cross-tier comparison

When two rows land in different tiers, the lower tier number wins — with one
exception: **tier-promotion via launch count**. A more-used app may jump up
by exactly one tier (so a frequently-used keyword match outranks a
never-launched generic match):

```cpp
if (!endpointInvolved && std::abs(leftRel - rightRel) <= 1
    && leftCount != rightCount) {
    return leftCount > rightCount;
}
```

The endpoint tiers are inviolate:

- **Tier 0** (prefix) — must always win. A heavily-used `Spotter` never
  beats a never-used `Terminal` for query `ter`.
- **Tier 4** (mid-word fallback) — must always lose. A heavily-used
  `ghostwriter` never beats a generic/keyword hit for query `ter`.

### Within-tier tiebreaks

Order, top to bottom:

1. **Mime default** — if one of the two is the user's mime default (e.g.
   default browser for an app that handles `text/html`), it wins.
2. **Launch count** (or frecency — see below) — higher count first.
3. **Alphabetical** — `QString::localeAwareCompare`.

## Frecency option (opt-in)

The Search config offers *"Prefer frequently-used apps in search results
(KActivities)"*. When on, `FrecencyProvider` runs a
`KActivities::Stats::ResultModel` query (`UsedResources | HighScoredFirst
| Url::startsWith("applications:") | Limit(200)`) and emits a
`storage-id → rank` map.

In `AppFilterModel::lessThan`, when the toggle is on **and** the map is
populated, the frecency rank substitutes for `launchCount` in *both* the
cross-tier promotion and the within-tier tiebreak — same code paths, time-
weighted input.

```cpp
const auto &counts = (m_searchUsesFrecency && !m_frecencyScores.isEmpty())
                         ? m_frecencyScores
                         : m_launchCounts;
```

If the toggle is off, or the KAStats query has not yet populated, the
ranking is bit-for-bit identical to the no-frecency path.

The grid sort deliberately stays off this (#95): the grid is for visual
scanning where stable, predictable ordering matters more than "what I used
lately". Search is already heuristic, so a frecency tiebreak fits the
spirit; the grid is not.

## Layering / decoupling

```
ConfigSearch.qml ──cfg.searchUsesFrecency──► main.qml
                                              │
                                              ▼
                                   Plasmoid.setSearchUsesFrecency(bool)
                                              │
                          ┌───────────────────┴───────────────────┐
                          ▼                                       ▼
                AppFilterModel                            FrecencyProvider
                .setSearchUsesFrecency(bool)              .setEnabled(bool)
                .setFrecencyScores(QHash…)  ◄──scoresChanged─┘
                                                (KActivities ResultModel)
```

- `AppFilterModel` knows nothing about KActivities — it consumes a plain
  `QHash<QString,int>`.
- `FrecencyProvider` knows nothing about `AppFilterModel` — it produces a
  `QHash<QString,int>`.
- `AppGridPlugin` is the composition root: owns both, wires them, exposes
  one `Q_INVOKABLE` for QML.

This is why `test_search_ranking` can exercise the frecency tiebreak with
nothing more than `setFrecencyScores({...})` and `setSearchUsesFrecency(true)`
— no KActivities runtime needed.

## Test coverage

`tests/test_search_ranking.cpp` covers every rule above:

- Tier ordering (`prefixBeatsSubstring`, `substringBeatsGeneric`,
  `genericBeatsKeyword`).
- Tier-promotion (`mostUsedJumpsOneTierUp`, `mostUsedCannotJumpTwoTiers`).
- Endpoint inviolability (`mostUsedCannotDethronePrefix`,
  `midwordSubstringStaysBelowKeywordEvenWhenUsed`,
  `wordBoundarySubstringBeatsMidword`).
- Tiebreaks (`launchCountTiebreaksWithinTier`,
  `defaultAppBeatsNonDefaultInSameTier`,
  `launchCountStillBeatsDefaultAcrossTiers`,
  `zeroCountDoesNotCrossTier`).
- Frecency substitution (`frecencyTiebreakReplacesLaunchCount`,
  `frecencyFallsBackToLaunchCountWhenMapEmpty`).
