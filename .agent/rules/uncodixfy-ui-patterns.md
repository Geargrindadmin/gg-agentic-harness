# Uncodixfy UI Patterns (Cherry-Picked)

Purpose: enforce anti-generic frontend output without importing external tooling.

Apply this rule when building new UI screens/components unless product design system explicitly conflicts.

## Hard Bans

1. Do not stack floating glass cards as default layout motif.
2. Do not default to oversized border radius everywhere.
3. Do not use decorative gradient-heavy dashboards as first choice.
4. Do not add non-functional decorative labels/chips for visual filler.
5. Do not use purple-first palette unless the product brand requires it.

## Required Construction Rules

1. Start from content hierarchy and user task flow before styling details.
2. Use one dominant visual language per screen (editorial, enterprise, brutalist, etc.) and keep it consistent.
3. Pick typography intentionally (display + body pairing), avoid generic defaults.
4. Prefer strong spacing rhythm and alignment over ornamental effects.
5. Every visual accent must have functional intent (state, affordance, hierarchy, feedback).

## Quality Checklist

1. Remove any element that exists only for decoration and does not improve comprehension.
2. Verify mobile and desktop layout integrity (no overlap or clipped controls).
3. Verify interaction clarity for hover/focus/disabled/loading states.
4. Confirm color contrast and readable text hierarchy.
5. Confirm output still fits existing product patterns when modifying existing surfaces.
