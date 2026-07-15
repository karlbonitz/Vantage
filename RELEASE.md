# Releasing Vantage — checklist

Work top to bottom. Never ships in the zip (`.pkgmeta` ignores it).

---

## 1. Bump FOUR things, not three

Three are obvious. The fourth is the one that got missed in v0.12.0 and would
have shipped: **the login "what's new" line is a hand-written string that does
not follow the version number.** Miss it and every upgrading player is told the
new feature is the *previous* release's headline.

- [ ] `Core/Util.lua` — `Vantage.version = "X.Y.Z"`
- [ ] `Vantage.toc` — `## Version: X.Y.Z`
- [ ] `CHANGELOG.md` — new top entry (this becomes the CurseForge/Wago changelog
      automatically via `.pkgmeta`'s `manual-changelog`)
- [ ] **`Core/Core.lua`** — the upgrade message in the `prev ~= Vantage.version`
      branch. Rewrite it to name *this* release's headliners.

## 2. Tests

```bash
python3 tests/run.py       # addon harness  -> both class archetypes green
node collector/test.mjs    # collector gate
```

Green tests are necessary, not sufficient — they run against stubs. See §7.

## 3. Repo hygiene

- [ ] Working tree clean; everything committed.
- [ ] **Every TOC-listed file is git-tracked.** A file that exists locally but is
      untracked works for you and is *absent from the release zip* — users get a
      broken addon. This nearly happened with `Data/CommunityPack.lua`.
      ```bash
      grep -vE '^\s*#|^\s*$|^##' Vantage.toc | while read -r f; do
        p=$(echo "$f" | tr '\\' '/')
        git ls-files --error-unmatch "$p" >/dev/null 2>&1 || echo "UNTRACKED: $p"
      done
      ```
- [ ] Check what will actually ship (should be `Core/ Data/ Media/ Modules/`,
      `Vantage.toc`, `CHANGELOG.md`, `LICENSE` — nothing else):
      ```bash
      git ls-files | grep -vE '^(tests/|docs/|collector/|\.github/)' \
                   | grep -vE '^(README\.md|LISTING\.md|RELEASE\.md|\.pkgmeta|\.gitignore)$'
      ```
- [ ] `README.md` / `LISTING.md` describe what actually ships. Docs drift fast —
      claims about dependencies, roadmap items, and the version in the install
      steps all rot silently.

## 4. In-game smoke test

Copy the folder to `_anniversary_/Interface/AddOns/Vantage`, then:

- [ ] **Fully restart the client** if any file was added or removed (see §7).
- [ ] Login banner prints the new version.
- [ ] `/vantage test` fires the cue.
- [ ] Exercise this release's new commands — every one of them, by hand.
- [ ] Anything group-gated (threat/amber, `/vantage kicks`, party watch) needs a
      **real group**. Solo, `ThreatEst` returns nil by design and amber never fires.
- [ ] `/vantage parse` at the end reports sane numbers.

## 5. Tag and ship

```bash
git push
git tag vX.Y.Z && git push --tags
```

`.github/workflows/release.yml` runs `BigWigsMods/packager@v2` on any `v*` tag and:
- builds `Vantage-vX.Y.Z-bcc.zip` per `.pkgmeta`
- uploads to **CurseForge** (project `1602039`, needs `CF_API_KEY`)
- uploads to **Wago** (`qKQm2EKx`, needs `WAGO_API_TOKEN`)
- attaches the zip to a **GitHub release**

Both secrets are set. Without them the run still builds and does the GitHub
release, so a failed store upload is not silent — check the Action.

- [ ] Action is green.
- [ ] GitHub release exists and the zip contains the addon (not the repo).

## 6. Posting — the manual half

**The packager never touches the long description.** It uploads the file and the
changelog; the store page prose only changes when you paste it.

- [ ] **CurseForge** → project `1602039` → description editor → paste `LISTING.md`.
- [ ] **Wago** → addon `qKQm2EKx` → description editor → paste `LISTING.md`.
- [ ] CurseForge may hold the listing in **moderation** briefly before it's
      publicly searchable. Wago usually goes live faster.
- [ ] `docs/index.html` (the report page) is served by GitHub Pages from `main` —
      pushing updates it. No separate deploy.

## 7. Hard-won gotchas

- **`/reload` cannot see files that didn't exist at client launch.** WoW indexes
  addon files at startup. Editing an existing file and `/reload`-ing works; adding
  or removing one needs a **full client restart**. A release that adds a module
  and is only `/reload`-ed will look half-broken in ways that make no sense.
- **Lua errors are silent by default.** `scriptErrors` defaults off, so "no errors"
  means nothing until you `/console scriptErrors 1` and `/reload`. Errors also land
  in `Logs/FrameXML.log`.
- **A stub that lies is worse than no stub.** Twice in the v0.12.0 cycle a
  `tests/wow_stub.lua` fiction kept CI green over broken code — once masking a dead
  fallback, once faking an entire library that never loaded in a real client. When
  a stub asserts a contract, that contract must have been observed in-game.
- **Verify a feature *executes* before documenting it.** v0.12.0 nearly shipped
  "real threat via an embedded library" for a library that returned at line 87 on
  every TBC client and had never run once.
</content>
