# Repository Governance Contract

Policy ID: `ng-repo-governance/1.0.0`
Last reviewed: 2026-08-27

## Identity

- Repository: `Yesol-Pilot/mochi-terminal-pets`
- Lifecycle class: `personal-open-source-project`
- Current and intended owner: `Yesol-Pilot`
- Canonical branch: `main`
- Visibility: `public`
- Transfer state: `NOT_REQUIRED`
- Production status: `PERSONAL_PROJECT`

## Purpose and boundaries

This repository is a personal terminal-pet project. It remains outside `NeoGenesisAI` unless a future explicit decision converts it into a maintained company product.

- Personal pet photos, veterinary records, addresses, location metadata, account information, and private device data are prohibited unless deliberately sanitized for public release.
- Public packages, binaries, screenshots, and examples require license, provenance, security, accessibility, and compatibility review.
- A cute or low-risk interface does not waive supply-chain, terminal escape, filesystem, process, update, or package-installation safety.

## Required controls

- [ ] Run full-history secret, dependency, license, image-metadata, terminal-escape, and package supply-chain audits.
- [ ] Add format, typecheck or compile, unit, terminal rendering, supported-shell, platform, installation, update, uninstall, accessibility, and rollback checks.
- [ ] Pin release artifacts to exact commits and publish checksums.
- [ ] Keep the project intentionally personal or record an explicit future ownership change.

## Pull-request and branch rules

- One task, one branch, one isolated worktree.
- Changes state package, platform, terminal, filesystem, personal-asset, release, and rollback impact.
- Review conversations resolve before squash merge.
- `main` is not force-pushed or deleted.

## Exit criteria

The repository is `ACTIVE_COMPLIANT` only when personal ownership is intentional, public assets are privacy-safe and licensed, supported platforms and release artifacts are verified, and rollback or uninstall works.

The presence of this file alone is not compliance.
