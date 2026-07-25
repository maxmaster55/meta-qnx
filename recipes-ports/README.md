# recipes-ports

`.bbappend` files for **stock recipes from other layers**, carrying the smallest
change that makes them build for QNX.

This directory is the exception to meta-qnx's "mechanism only, no policy" rule, and it
is worth being clear about why it is allowed to exist and what it may not become.

## What belongs here

Only things that are true of the *recipe on QNX*, not of any particular product:

- Trimming a `PACKAGECONFIG` whose default pulls something that does not exist on QNX.
- A configure or link flag QNX needs and Linux does not.
- Disabling a component of a recipe that is inherently Linux-bound.

Every entry must be guarded by the machine override, so the append is inert in a build
for any other target:

```bitbake
PACKAGECONFIG:qnx-aarch64le = "zlib"
```

## What does not belong here

- **Selecting features because a product wants them.** "We need harfbuzz" is a project
  decision; it goes in the project layer or `local.conf`, as `PACKAGECONFIG:pn-freetype`.
- **Anything with a fix that is generic.** If two recipes need the same thing, it is a
  toolchain problem — put it in `qnx-toolchain.bbclass` instead. That class exists so
  this directory stays small.
- **Patches to upstream source.** A recipe needing code changes is the Tier 2 case in
  [docs/reusing-layers.md](../docs/reusing-layers.md), and belongs in a layer that owns
  the port, not in the layer that provides the mechanism.

## Current contents

| Recipe | From | Change | Why |
| --- | --- | --- | --- |
| `freetype` | oe-core | drop `pixmap` from `PACKAGECONFIG` | pulls libpng; nothing here needs freetype's PNG loader |

If this table grows past a handful of rows, that is a signal the fixes have stopped
being per-recipe accidents and should be generalised somewhere else.
