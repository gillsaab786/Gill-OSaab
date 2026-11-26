# Gill(OS): rules for Claude sessions (keep short; loaded every turn)
- Terse replies. No preamble, no recap, no unasked suggestions. Answer first.
- Read a file once; targeted Edit over full rewrites. No over-engineering.
- Filter CI logs (grep PASS/FAIL/error); never dump full logs.
- Test via CI before calling anything done: shell.yml (headless desktop + screenshots on
  ci-shots), build.yml (images), core-smoke.yml (real Core image, core-shots), iso.yml.
- On a failing step: find the first real error, fix it, re-run. Don't guess repeatedly.
- Never `dnf remove` in image builds (it cascades: removing gcc took Wine with it).
- Status and next steps live in shell/ROADMAP.md.
