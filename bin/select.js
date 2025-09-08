#!/usr/bin/env node
// Interactive multi-select helper for bash-zoo using a modern
// enquirer-based UX (arrows + space + enter).
//
// Reads a JSON payload from stdin of the form:
//   { title?: string, choices: [{ name: string, message?: string }] }
// Emits selected item names to stdout, one per line.

const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

function requireEnquirer() {
  // Try normal resolution first
  try { return require('enquirer'); } catch (_) {}
  // Then try local vendored path: ../.interactive/node_modules
  try {
    const vendorRoot = path.resolve(__dirname, '..', '.interactive');
    const req = createRequire(path.join(vendorRoot, 'package.json'));
    return req('enquirer');
  } catch (e) {
    console.error('Failed to load enquirer. The wizard attempts to auto-install it.');
    process.exit(1);
  }
}

async function main() {
  let json = process.env.BZ_PAYLOAD || '';
  if (!json && process.argv[2]) {
    try { json = fs.readFileSync(process.argv[2], 'utf8'); } catch {}
  }
  if (!json && process.stdin.isTTY === false) {
    try { json = fs.readFileSync(0, 'utf8'); } catch {}
  }

  let data;
  try {
    data = JSON.parse(json);
  } catch (e) {
    console.error('Invalid or missing JSON payload for select.js');
    process.exit(1);
  }

  const enquirer = requireEnquirer();
  const { MultiSelect } = enquirer;

  const title = data.title || 'Select one or more items';
  const choices = (data.choices || []).map((c) => ({
    name: String(c.name),
    message: c.message ? String(c.message) : String(c.name),
    value: String(c.name),
  }));

  const prompt = new MultiSelect({
    name: 'selection',
    message: title,
    choices,
    // Enable intuitive keybindings with space to toggle and arrows to move
    hint: 'Use arrow keys to move, space to select, enter to confirm',
    // show at least 10 lines if possible for comfort
    limit: Math.max(10, Math.min(choices.length, 20)),
    // Route UI rendering to stderr so stdout stays clean for results
    stdin: process.stdin,
    stdout: process.stderr,
  });

  try {
    const selected = await prompt.run();
    // Print one per line for easy parsing in bash
    (Array.isArray(selected) ? selected : [selected]).forEach((name) => {
      process.stdout.write(String(name) + '\n');
    });
  } catch (e) {
    // If user cancels, exit cleanly with no selection
    process.exit(0);
  }
}

main();
