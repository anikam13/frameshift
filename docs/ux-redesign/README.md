# FrameShift UX Redesign Package

This package captures the selected UX direction after extensive design discussions. It is intended for browser-based visual iteration (e.g. Google Stitch / Figma) and later native iOS implementation.

- `DESIGN.md`: visual principles, target components, style direction, anti-patterns.
- `UX-SPEC.md`: navigation, interactions, state behavior, persistence and edge cases.
- `SCREEN-INVENTORY.md`: list of screens/states to design and prototype, with acceptance checks.
- `STITCH-PROMPT.md`: ready-to-paste generation brief.
- `current-screens/`: nine original app screenshots for reference only.

## Recommended order
1. Read the README and DESIGN + UX specs.
2. Upload the existing screenshots into your design tool.
3. Paste the Stitch prompt; import design rules if supported by your tool.
4. Generate only 4 core screens at first; compare alternatives and refine.
5. Prototype navigation and first-use camera behaviors.
6. Review remaining unconfirmed decisions, then finalize tokens and extend to remaining states.
7. When Claude Code credits return, provide approved mockups and the final specs as implementation constraints.

**Important:** The spec distinguishes approved decisions from provisional recommendations. It is not a claim that every detail is already implemented or technically validated.
