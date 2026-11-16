# Contributing to GameFixes_mm

Thank you for your interest in contributing to **GameFixes_mm**, maintained by **SyntX** and **Denied** for the **Nova Zombie Community** (originally created by Michal "Slynx" Přikryl).

## Getting Started

1. Fork the repository and create a new branch from `main`.
2. Make your changes following the project's coding style:
   - Use `/* ... */` block comments for C/C++ code comments.
   - Keep functions focused and avoid unnecessary abstractions.
   - Preserve existing license headers and credits.
3. Test your changes (CI automatically compiles both Linux and Windows builds on every push and pull request).
4. Open a pull request against `main` with a clear description of what was changed and why.

## Commit Messages

Use clear, descriptive commit messages (Conventional Commits format is recommended, e.g. `fix(slow_animation): ...`, `feat(...): ...`).

## Reporting Bugs

Open an issue with:
- CS2 server OS (Linux or Windows)
- Metamod:Source & GameFixes_mm version (`meta list`)
- Relevant `game_fixes.ini` configuration
- Steps to reproduce and server console logs
