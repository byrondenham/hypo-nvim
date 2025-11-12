# Contributing to hypo-nvim

Thanks for your interest in contributing! This file describes how to set up your environment for development, keep your changes formatted, and create PRs.

## Format code

We use stylua to format Lua files. Locally, install stylua (via cargo) and run the check or formatter:

Install (one-time):
```bash
# Requires Rust toolchain (rustup / cargo)
cargo install stylua
```

Check formatting:
```bash
stylua --check .
```

Format in-place:
```bash
stylua .
```

If you prefer not to install stylua locally, you can run it inside a container or rely on CI to report formatting issues.

## Run (smoke) tests

If this repository later adds tests, run them locally with:
```bash
# Example: adapt to your test harness
nvim --headless -c 'lua require("plenary.test_harness").run()' -c 'qa'
```

## Branching and PRs

1. Create a descriptive branch from main:
```bash
git checkout -b chore/short-description
```

2. Make your changes, run formatting:
```bash
stylua .
```

3. Commit and push:
```bash
git add .
git commit -m "chore: short description"
git push origin HEAD
```

4. Open a PR on GitHub and include a short description of the change and any testing steps.

## Reporting bugs / feature requests

Please open issues describing the behavior you observed, steps to reproduce, and any relevant logs or screenshots.

Thanks — maintainers will review PRs as soon as possible.
``` ````

Step-by-step commands to add these files and open a PR
1. Create a branch locally:
   - git checkout -b chore/add-ci-and-legal

2. Add the files (you can create them with your editor or echo > file):
   - Create directory for workflow:
     - mkdir -p .github/workflows
   - Add the files with your editor or paste the contents above into:
     - .github/workflows/ci.yml
     - stylua.toml
     - LICENSE
     - CONTRIBUTING.md

3. Stage, commit, push:
   - git add .github/workflows/ci.yml stylua.toml LICENSE CONTRIBUTING.md
   - git commit -m "chore(ci): add workflow; add stylua config, LICENSE, CONTRIBUTING"
   - git push -u origin chore/add-ci-and-legal

4. Open a PR
   Option A — GitHub web: go to the repository page and create a new pull request from your branch.
   Option B — GitHub CLI (if installed):
   - gh auth login    # if not already logged in
   - gh pr create --title "chore: add CI, stylua config, LICENSE, CONTRIBUTING" --body "Adds CI workflow that runs stylua checks; adds stylua.toml, LICENSE (MIT), and CONTRIBUTING.md." --base main

Notes, caveats, and suggestions
- The CI workflow uses cargo to install stylua. If you prefer a different installation path or a pinned stylua release, adjust the workflow step accordingly. If you use a CI container that already has stylua, remove the installation step.
- You can expand the CI to run unit tests (Neovim headless tests) or additional linters (luacheck, etc.) later.
- If you want me to actually create these files and open a PR in byrondenham/hypo-nvim now, tell me and I will: (a) create a branch, (b) push these files, and (c) open a PR. I will then include the PR link and the exact diff. 

I've shown the exact contents for each required file and the exact git commands to add them. Tell me if you want me to (A) make the changes and open the PR now, or (B) modify any file contents, or (C) include extra optional files (Telescope adapter, API adapter stub, parse/fmt utils) next.
