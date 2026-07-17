# Project governance

## Roles

- **Maintainers** define milestones, approve architecture decisions, review pull
  requests, and manage releases.
- **Module owners** drive an assigned area and keep its interfaces, tests, and
  documentation current.
- **Contributors** own accepted Issues and receive credit through commits and
  pull requests.

XP Liu (`@UILPX`) is the founding maintainer and default reviewer. Additional
maintainers and module owners may be added after sustained, reviewed
contributions. Collaborator access does not erase individual authorship or imply
ownership of work written by someone else.

## Current ownership

| Area | Lead | Required reviewer |
| --- | --- | --- |
| Architecture and interfaces | Unassigned | `@UILPX` |
| Build and CI | Unassigned | `@UILPX` |
| Frontend and prediction | Unassigned | `@UILPX` |
| Rename, scheduling, and commit | Unassigned | `@UILPX` |
| Execute units | `@UILPX` | `@UILPX` |
| Memory system | `@UILPX` | `@UILPX` |
| Verification and formal | Unassigned | `@UILPX` |
| Synthesis, timing, and PPA | Unassigned | `@UILPX` |

Ownership is claimed through an Issue and confirmed by a maintainer. It is not
permanent; inactive or blocked areas may be reassigned after discussion.

## Decisions

- Local implementation choices are resolved in the task pull request.
- Changes to public interfaces, pipeline contracts, ISA behavior, or milestone
  scope require a design-proposal Issue before RTL is written.
- Prefer measured, reversible decisions. Record rejected alternatives and the
  evidence used to choose.
- If consensus is not reached, the founding maintainer makes the decision and
  documents the reason in the Issue.

## Merging and releases

Work targets `main` through pull requests. Do not force-push or delete `main`.
The repository owner may bypass protection only for repository recovery or a
clearly documented administrative change. Releases require a clean regression,
reproducible tool versions, and results tied to a commit.
