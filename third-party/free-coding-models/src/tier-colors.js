/**
 * @file tier-colors.js
 * @description Chalk colour functions for each tier level, extracted from bin/free-coding-models.js.
 *
 * @details
 *   The tier system maps model quality tiers (S+, S, A+, A, A-, B+, B, C) to a
 *   green → yellow → orange → red gradient.  Keeping these colour definitions in their
 *   own module allows the renderer, overlays, and any future CLI tools to share a
 *   single, consistent visual language without depending on the whole TUI entry point.
 *
 *   The gradient is deliberately designed so that the higher the tier the more
 *   "neon" and attention-grabbing the colour, while lower tiers fade toward dark red.
 *   `chalk.rgb()` is used for fine-grained control — terminal 256-colour and truecolour
 *   modes both support this; on terminals that don't, chalk gracefully degrades.
 *
 * @exports
 *   TIER_COLOR — object mapping tier string → chalk colouring function
 *
 * @see src/constants.js   — TIER_CYCLE ordering that drives the T-key filter
 * @see bin/free-coding-models.js — renderTable() uses TIER_COLOR per row
 */

import chalk from 'chalk'

// 📖 Tier colors: green gradient (best) → yellow → orange → red (worst).
// 📖 Uses chalk.rgb() for fine-grained color control across 8 tier levels.
// 📖 Each entry is a function (t) => styled string so it can be applied to any text.
export const TIER_COLOR = {
  'S+': t => chalk.bold.rgb(0,   255,  80)(t),   // 🟢 bright neon green  — elite
  'S':  t => chalk.bold.rgb(80,  220,   0)(t),   // 🟢 green              — excellent
  'A+': t => chalk.bold.rgb(170, 210,   0)(t),   // 🟡 yellow-green       — great
  'A':  t => chalk.bold.rgb(240, 190,   0)(t),   // 🟡 yellow             — good
  'A-': t => chalk.bold.rgb(255, 130,   0)(t),   // 🟠 amber              — decent
  'B+': t => chalk.bold.rgb(255,  70,   0)(t),   // 🟠 orange-red         — average
  'B':  t => chalk.bold.rgb(210,  20,   0)(t),   // 🔴 red                — below avg
  'C':  t => chalk.bold.rgb(140,   0,   0)(t),   // 🔴 dark red           — lightweight
}
