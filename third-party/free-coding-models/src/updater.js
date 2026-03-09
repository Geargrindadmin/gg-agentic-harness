/**
 * @file updater.js
 * @description Update detection and installation helpers, extracted from bin/free-coding-models.js.
 *
 * @details
 *   This module handles all npm version-check and auto-update logic:
 *
 *   - `checkForUpdateDetailed()` — hits the npm registry to compare the published version
 *     against the locally installed one.  Returns `{ latestVersion, error }` so callers
 *     can surface meaningful status text in the Settings overlay.
 *
 *   - `checkForUpdate()` — thin backward-compatible wrapper used at startup for the
 *     auto-update guard.  Returns `latestVersion` (string) or `null`.
 *
 *   - `runUpdate(latestVersion)` — runs `npm i -g free-coding-models@<version> --prefer-online`,
 *     retrying with `sudo` on EACCES/EPERM.  On success, relaunches the process with the
 *     same argv.  On failure, prints manual instructions and exits with code 1.
 *     Uses `require('child_process').execSync` inline because ESM dynamic import is async
 *     but `execSync` must block to give `stdio: 'inherit'` feedback in the terminal.
 *
 *   - `promptUpdateNotification(latestVersion)` — renders a small centered interactive menu
 *     that lets the user choose: Update Now / Read Changelogs / Continue without update.
 *     Uses raw mode readline keypress events (same pattern as the main TUI).
 *     This function is called BEFORE the alt-screen is entered, so it writes to the
 *     normal terminal buffer.
 *
 *   ⚙️ Notes:
 *   - `LOCAL_VERSION` is resolved from package.json via `createRequire` so this module
 *     can be imported independently from the bin entry point.
 *   - The auto-update flow in `main()` skips update if `isDevMode` is detected (presence of
 *     a `.git` directory next to the package root) to avoid an infinite update loop in dev.
 *
 * @functions
 *   → checkForUpdateDetailed()           — Fetch npm latest with explicit error info
 *   → checkForUpdate()                   — Startup wrapper, returns version string or null
 *   → runUpdate(latestVersion)           — Install new version via npm global + relaunch
 *   → promptUpdateNotification(version)  — Interactive pre-TUI update menu
 *
 * @exports
 *   checkForUpdateDetailed, checkForUpdate, runUpdate, promptUpdateNotification
 *
 * @see bin/free-coding-models.js — calls checkForUpdate() at startup and runUpdate() on confirm
 */

import chalk from 'chalk'
import { createRequire } from 'module'

const require = createRequire(import.meta.url)
const readline = require('readline')
const pkg = require('../package.json')
const LOCAL_VERSION = pkg.version

/**
 * 📖 checkForUpdateDetailed: Fetch npm latest version with explicit error details.
 * 📖 Used by settings manual-check flow to display meaningful status in the UI.
 * @returns {Promise<{ latestVersion: string|null, error: string|null }>}
 */
export async function checkForUpdateDetailed() {
  try {
    const res = await fetch('https://registry.npmjs.org/free-coding-models/latest', { signal: AbortSignal.timeout(5000) })
    if (!res.ok) return { latestVersion: null, error: `HTTP ${res.status}` }
    const data = await res.json()
    if (data.version && data.version !== LOCAL_VERSION) return { latestVersion: data.version, error: null }
    return { latestVersion: null, error: null }
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return { latestVersion: null, error: message }
  }
}

/**
 * 📖 checkForUpdate: Backward-compatible wrapper for startup update prompt.
 * @returns {Promise<string|null>}
 */
export async function checkForUpdate() {
  const { latestVersion } = await checkForUpdateDetailed()
  return latestVersion
}

/**
 * 📖 runUpdate: Run npm global install to update to latestVersion.
 * 📖 Retries with sudo on permission errors.
 * 📖 Relaunches the process on success, exits with code 1 on failure.
 * @param {string} latestVersion
 */
export function runUpdate(latestVersion) {
  const { execSync } = require('child_process')
  console.log()
  console.log(chalk.bold.cyan('  ⬆ Updating free-coding-models to v' + latestVersion + '...'))
  console.log()

  try {
    // 📖 Force install from npm registry (ignore local cache)
    // 📖 Use --prefer-online to ensure we get the latest published version
    execSync(`npm i -g free-coding-models@${latestVersion} --prefer-online`, { stdio: 'inherit' })
    console.log()
    console.log(chalk.green('  ✅ Update complete! Version ' + latestVersion + ' installed.'))
    console.log()
    console.log(chalk.dim('  🔄 Restarting with new version...'))
    console.log()

    // 📖 Relaunch automatically with the same arguments
    const args = process.argv.slice(2)
    execSync(`node ${process.argv[1]} ${args.join(' ')}`, { stdio: 'inherit' })
    process.exit(0)
  } catch (err) {
    console.log()
    // 📖 Check if error is permission-related (EACCES or EPERM)
    const isPermissionError = err.code === 'EACCES' || err.code === 'EPERM' ||
                             (err.stderr && (err.stderr.includes('EACCES') || err.stderr.includes('permission') ||
                                              err.stderr.includes('EACCES'))) ||
                             (err.message && (err.message.includes('EACCES') || err.message.includes('permission')))

    if (isPermissionError) {
      console.log(chalk.yellow('  ⚠️ Permission denied. Retrying with sudo...'))
      console.log()
      try {
        execSync(`sudo npm i -g free-coding-models@${latestVersion} --prefer-online`, { stdio: 'inherit' })
        console.log()
        console.log(chalk.green('  ✅ Update complete with sudo! Version ' + latestVersion + ' installed.'))
        console.log()
        console.log(chalk.dim('  🔄 Restarting with new version...'))
        console.log()

        // 📖 Relaunch automatically with the same arguments
        const args = process.argv.slice(2)
        execSync(`node ${process.argv[1]} ${args.join(' ')}`, { stdio: 'inherit' })
        process.exit(0)
      } catch (sudoErr) {
        console.log()
        console.log(chalk.red('  ✖ Update failed even with sudo. Try manually:'))
        console.log(chalk.dim('    sudo npm i -g free-coding-models@' + latestVersion))
        console.log()
      }
    } else {
      console.log(chalk.red('  ✖ Update failed. Try manually: npm i -g free-coding-models@' + latestVersion))
      console.log()
    }
  }
  process.exit(1)
}

/**
 * 📖 promptUpdateNotification: Show a centered interactive menu when a new version is available.
 * 📖 Returns 'update', 'changelogs', or null (continue without update).
 * 📖 Called BEFORE entering the alt-screen so it renders in the normal terminal buffer.
 * @param {string|null} latestVersion
 * @returns {Promise<'update'|'changelogs'|null>}
 */
export async function promptUpdateNotification(latestVersion) {
  if (!latestVersion) return null

  return new Promise((resolve) => {
    let selected = 0
    const options = [
      {
        label: 'Update now',
        icon: '⬆',
        description: `Update free-coding-models to v${latestVersion}`,
      },
      {
        label: 'Read Changelogs',
        icon: '📋',
        description: 'Open GitHub changelog',
      },
      {
        label: 'Continue without update',
        icon: '▶',
        description: 'Use current version',
      },
    ]

    // 📖 Centered render function
    const render = () => {
      process.stdout.write('\x1b[2J\x1b[H') // clear screen + cursor home

      // 📖 Calculate centering
      const terminalWidth = process.stdout.columns || 80
      const maxWidth = Math.min(terminalWidth - 4, 70)
      const centerPad = ' '.repeat(Math.max(0, Math.floor((terminalWidth - maxWidth) / 2)))

      console.log()
      console.log(centerPad + chalk.bold.red('  ⚠ UPDATE AVAILABLE'))
      console.log(centerPad + chalk.red(`  Version ${latestVersion} is ready to install`))
      console.log()
      console.log(centerPad + chalk.bold('  ⚡ Free Coding Models') + chalk.dim(` v${LOCAL_VERSION}`))
      console.log()

      for (let i = 0; i < options.length; i++) {
        const isSelected = i === selected
        const bullet = isSelected ? chalk.bold.cyan('  ❯ ') : chalk.dim('    ')
        const label = isSelected
          ? chalk.bold.white(options[i].icon + ' ' + options[i].label)
          : chalk.dim(options[i].icon + ' ' + options[i].label)

        console.log(centerPad + bullet + label)
        console.log(centerPad + chalk.dim('       ' + options[i].description))
        console.log()
      }

      console.log(centerPad + chalk.dim('  ↑↓ Navigate  •  Enter Select  •  Ctrl+C Continue'))
      console.log()
    }

    render()

    readline.emitKeypressEvents(process.stdin)
    if (process.stdin.isTTY) process.stdin.setRawMode(true)

    const onKey = (_str, key) => {
      if (!key) return
      if (key.ctrl && key.name === 'c') {
        if (process.stdin.isTTY) process.stdin.setRawMode(false)
        process.stdin.removeListener('keypress', onKey)
        resolve(null) // Continue without update
        return
      }
      if (key.name === 'up' && selected > 0) {
        selected--
        render()
      } else if (key.name === 'down' && selected < options.length - 1) {
        selected++
        render()
      } else if (key.name === 'return') {
        if (process.stdin.isTTY) process.stdin.setRawMode(false)
        process.stdin.removeListener('keypress', onKey)
        process.stdin.pause()

        if (selected === 0) resolve('update')
        else if (selected === 1) resolve('changelogs')
        else resolve(null) // Continue without update
      }
    }

    process.stdin.on('keypress', onKey)
  })
}
