# Explore feed

New Explore references without an app update. The app fetches
`https://anikam13.github.io/frameshift-explore/manifest.json` once per launch
(`Services/RemoteReferenceFeed.swift`), downloads photos it doesn't have,
analyzes them on-device like any import, and keeps them offline afterwards.
The bundled `SampleReferencePack` remains the offline / first-launch set.

## Add a photo

```bash
./add-reference.sh ~/Downloads/rooftop.jpg women fullBody
./publish.sh
```

- Subject: `women` or `men` (Explore's toggle).
- Tags (any): `fullBody`, `portraits`, `seated`, `couples`, `groups`.
  Untagged photos fall back to Vision framing for the chips.
- New entries go to the top of Explore.

## Remove a photo

```bash
./remove-reference.sh <id>
./publish.sh
```

Users who favorited it keep it; everyone else loses it on next launch.

## Rules

- `id`s are permanent — never reuse one (the app keys photos by it).
- Images must sit beside the manifest on the same host (https only).
- Keep `version: 1`; bump only for a breaking format change (older apps then ignore the feed).
- Only publish photos you have rights to show in the app.

## One-time setup

The Pages repo `anikam13/frameshift-explore` (public, Pages from `main` / root).
`publish.sh` clones it, syncs this folder in, commits and pushes.
