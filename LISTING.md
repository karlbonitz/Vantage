# Vigil — listing copy for CurseForge / Wago

Paste-ready project description. Kept out of the packaged zip via `.pkgmeta`.

---

**Know exactly when to kick — and when not to waste it.**

Vigil is a zero-config interrupt and CC coach built into your nameplates, for
TBC Classic (Anniversary). It reads **your** kit — your class, your cooldowns,
even your pet and stance — and lights up the plate the moment acting matters:

- 🔔 **The interrupt cue.** A kickable enemy cast starts while your interrupt
  is ready → the nameplate erupts: glow, sound, and an `INTERRUPT` prompt
  centered on the plate. No window shown if your kick is on cooldown — when
  Vigil lights up, it means *now*.
- 🔒 **The padlock.** Casts that must NOT be kicked (uninterruptible boss
  casts, wasted-kick traps) get a padlock instead, so you hold your cooldown.
- 🛑 **Every class, not just kickers.** No hard interrupt? Vigil offers your
  real answer instead — `FEAR`, `STUN`, `SILENCE`, `SHACKLE` — and it checks
  target immunities first, so it never tells you to fear a fear-immune boss.
  Warrior stances, Druid forms, shields, combo points, and Felhunter/pet
  abilities are all understood.
- ⚔️ **PvP mode.** Against enemy players no spell database is needed — any
  hard cast is fair game, so the cue works in arena, battlegrounds, and world
  PvP at any level.
- ✨ **A full nameplate skin** (toggleable): gradient health bars, crisp 1px
  borders, class colors, level text, a slim mana bar on casters, health text,
  gold target glow, bordered cast-bar icon with a live countdown, and your
  DoT/debuff timers with dispel-colored borders and a cooldown swipe.
- 📊 **Vigil Parse.** The stat Warcraft Logs can't show you: how many casts
  you *let through while your kick sat ready*. Vigil logs every decision it
  shows you, plus your cue→kick reaction time. `/vigil export`, paste into the
  free report page — everything decodes in your browser, nothing is uploaded:
  https://karlbonitz.github.io/Vigil/

**Zero configuration.** Install it and pull a caster pack — the defaults are
tuned. Everything is toggleable via `/vigil` (a native options panel).

**Zero dependencies.** No libraries, decorates the default Blizzard plates
(plays nice with taint), instant load.

Interruptibility comes from a hand-curated, verified spell database covering
all TBC heroics, Karazhan, Gruul/Magtheridon, and SSC/Tempest Keep — not from
the client's unreliable `notInterruptible` flag.

*Early release: the Intel Pack keeps growing. Found a cast Vigil got wrong?
Report it on GitHub: https://github.com/karlbonitz/Vigil/issues*
