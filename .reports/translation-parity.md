# Translation parity — bazaar

| | |
|---|---|
| Upstream | `main` @ `3d347d5` |
| Port | `ruby` @ `cc88d35` |
| Domain | `io.github.kolunmi.Bazaar` (upstream's `.mo`/app-id domain — unconfirmed source, see below) |
| Upstream messages (non-po source) | 803 |
| Ported | 0 |
| Gaps | 803 |
| Extra (untranslated) | 0 |
| Upstream languages | 31 `.po` files in `po/` |
| Languages shipped by the port | 0 |
| Build command | none — the port has no gettext dependency at all |

## Step 1 — census

```sh
scripts/msgid-census.sh /tmp/bazaar-upstream > upstream-msgids.tsv   # 20068 rows (incl. po/)
awk -F'\t' '$4 !~ /^po\//' upstream-msgids.tsv | cut -f1,2 | sort -u | wc -l   # 803 distinct source messages
ls /tmp/bazaar-upstream/po/*.po | wc -l   # 31

scripts/msgid-census.sh .  (the ruby branch) > port-msgids.tsv   # 0 rows
```

**The port's census is empty: zero rows.** `grep -rn 'gettext\|_('
lib/*.rb` finds nothing. `Gemfile` and `bazaar-rb.gemspec` declare no
gettext dependency. There is no `po/` directory, no `LINGUAS`, no
`POTFILES.in`, no `.mo` build step, anywhere in the `ruby` branch.

## Step 2 — the diff

```
summary:
  ported: 0
  gaps: 803
  extra: 0
  languages: {upstream: 31, port: 0}
  domain_matches: false
  parity: false
```

Every one of upstream's 803 distinct source messages is a gap. There is no
partial credit: every user-visible string the port does build is a bare
English literal with no translation marker around it, which is not merely
"untranslated today" but structurally unrecoverable without a rewrite —
`_()`/`n_()` calls would need to be added at each of those sites and their
msgids transcribed byte-for-byte from upstream, not retyped.

## Step 3 — what this costs, concretely

- **31 languages that upstream ships today reach zero users of the port.**
  Not "0 of 78" as in some other forks in this org — this upstream carries
  31 `.po` files — but the finding is the same shape: `0 of 31` is the
  headline, and a raw "messages ported" count would have hidden it.
- Every label in the ~15 units the port does build (window menus, library
  page, about/shortcuts/preferences/error dialogs, settings) is English-only
  and will stay English-only in any locale, because nothing marks the
  strings and nothing loads a catalogue.
- The 68 unbuilt units (`.reports/component-parity.md`) contribute their
  share of the 803 messages too — closing the translation gap for a string
  that belongs to an unbuilt widget waits on the component, same as the
  skill's rule states; none of those rows can become `ported` before the
  widget exists.

## Step 4 — what is not run, and must not be reported as passing

`msgfmt`/`rmsgfmt` validation, a `.mo` build, and a `LANGUAGE=xx` screen
check were not run, because there is nothing to run them against: no
gettext call in the port, no catalogue, no domain. Reporting
`summary.parity: true` or any partial translation claim here would be a
false green — the correct and only honest statement is that this axis has
not been started at all.

## Rules re-affirmed

- No reword, no partial credit, no "English only for now" — the ledger
  states 0/803, 0/31 languages, flatly.
- This is recorded as a gap, never excused by the absence of a `PORTING.md`
  or by the binding limitations noted elsewhere in `lib/` (those are
  separately real — see `.reports/accountability-ensurance.md` — but they
  explain none of this: gettext is a plain Ruby gem with no GTK/Adwaita
  binding dependency at all, so this gap has no binding-limitation excuse
  available to it).
