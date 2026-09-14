# Hosted release and dependency response

Goal: publish the reviewed transport at an immutable hosted version, prove a clean consumer can resolve it, and provide the exact Genkit unblock response. Prerequisites: endpoint-binding, deterministic, live, mobile, secret-scan, documentation, and archive gates all pass.

## Release identity

The planned first hosted identity is:

- package: `opencode_auth`;
- version: `0.1.0`;
- tag: `v0.1.0`;
- source: the full commit SHA containing the final reviewed binding and verification contract;
- public binding symbol: `OpenCodeEndpointBinding`;
- required provider value: `OpenCodeEndpointBinding.subscriptionGo`;
- provider inspection point: `OpenCodeAuthClient.endpointBinding`;
- explicit custom constructor: `OpenCodeAuthOptions.custom`.

The repository already declares `0.1.0`, but that version is not hosted as of planning. Keep `0.1.0` for the completed first release rather than publishing the pre-binding source. Immediately before release, recheck `https://pub.dev/api/packages/opencode_auth`, repository tags, and GitHub releases. Stop if the name/version is occupied or remote state conflicts. Matt owns any rename/version decision and must update every plan/request/downstream reference before implementation continues.

## Pre-publication gate

From a clean repository root, record redacted pass/fail evidence for:

```sh
dart --version
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart doc --validate-links
gitleaks_bin_dir=$(mktemp -d)
./tool/install_gitleaks.sh "$gitleaks_bin_dir"
"$gitleaks_bin_dir/gitleaks" version
"$gitleaks_bin_dir/gitleaks" git --redact --config .gitleaks.toml
"$gitleaks_bin_dir/gitleaks" dir --redact --config .gitleaks.toml .
dart pub publish --dry-run
```

Require the version command to identify `8.30.1`. Remove only the created temporary installer directory after the scans; do not use an unresolved or broad deletion target.

Use the implemented live launcher with only variable names in retained commands. Run the mobile commands from [02-verification-contract.md](02-verification-contract.md). Confirm the worktree is clean, `pubspec.yaml` and `CHANGELOG.md` agree on `0.1.0`, README names the exact tested tuple, and the publish archive contains no evidence or secret-bearing files.

Matt or the accepted maintainer reviews the public API diff, test evidence, archive manifest, and response draft. Record explicit maintainer acceptance without credentials. Before pushing release state, the publication operator authenticates to pub.dev with the account that will become the first uploader, confirms it can perform the first upload flow, and rechecks package-name availability. Authentication details are not retained.

Create and review the release commit after that gate, verify its full SHA, and push the commit through the repository's normal reviewed workflow without a version tag. Publish from that exact clean commit. Keep the proposed annotated `v0.1.0` tag local/uncreated until pub.dev accepts the version, then create it at the unchanged published commit, verify its dereferenced SHA, and push it. Create any GitHub release only after the hosted version and remote tag agree.

The first pub.dev upload requires the authenticated human uploader. Run `dart pub publish` from the clean reviewed commit without `--skip-validation`. Do not add publication credentials to files, shell history excerpts, CI logs, or the response. Wait until pub.dev's package API and version page expose `0.1.0`, then verify its content hash and source link where available before creating/pushing the tag.

## Clean hosted-consumer gate

Create a fresh temporary directory outside this checkout with `mktemp -d`. Generate a minimal Dart console package that has no workspace membership, path dependency, Git dependency, `dependency_overrides`, or pre-existing lockfile. Add exact direct hosted dependencies `opencode_auth: 0.1.0` and `http: 1.6.0` from the default registry.

The **new temporary** `bin/consumer_smoke.dart` under the generated consumer directory is not a repository artifact. It imports `package:opencode_auth/opencode_auth.dart` plus the directly declared `package:http/io_client.dart` and compiles/tests:

- subscription options construction with an injected `IOClient`;
- `OpenCodeAuthClient.endpointBinding == OpenCodeEndpointBinding.subscriptionGo`;
- custom construction reports `custom` without exposing its URL in `toString()`;
- public request, cancellation, and exception matching symbols remain usable;
- auth close precedes borrowed `IOClient` close.

Run `dart pub get` and `dart test` or `dart run` in that consumer. Inspect its `pubspec.lock` to require hosted sources, exact `opencode_auth` `0.1.0`, exact `http` `1.6.0`, both registry content hashes, and no path/Git/override source. Delete the temporary directory after recording safe pass/fail, resolved versions, and content hashes. The hashes are public integrity metadata, not credentials.

A source commit, Git dependency, local path, mutable branch, dry-run, or maintainer acknowledgement does not pass this gate.

## Dependency response

Create **proposed new external directory** `$HOME/.agents/projects/opencode-auth-dart/responses/` beneath the verified existing project directory, then create the **new external planning handoff output during implementation** at `$HOME/.agents/projects/opencode-auth-dart/responses/2026-09-14-genkit-provider-release-pin.md`. Resolve `$HOME/.agents/projects/opencode-auth-dart` first, create only its direct `responses` child, resolve it again to reject a symlink escape, and verify the response file is a direct child before writing.

The response must include:

- request title/date and final status;
- explicit acceptance by Matt or the accepted `opencode_auth` maintainer;
- package `opencode_auth` and hosted `0.1.0` pin;
- `OpenCodeEndpointBinding`, `OpenCodeEndpointBinding.subscriptionGo`, `OpenCodeEndpointBinding.custom`, `OpenCodeAuthClient.endpointBinding`, and `OpenCodeAuthOptions.custom`;
- the rule that default construction alone grants the fixed subscription binding and custom construction never does, even with production URL text;
- annotated tag, full source commit, hosted content hash, and package/source links;
- exact `deepseek-v4-flash`, Chat Completions, Flutter, Dart, `http`, `IOClient`, iPhone/iOS, and AYN Thor/Android firmware tuple actually tested;
- redacted results for formatting, analysis, unit/provider-shaped, real TLS transport, live tool exchange, cancellation, connection loss, mobile, secret scan, docs, publish dry-run, and clean consumer;
- the two-request dispatch count and stable-identity equality result without the identity values;
- known limits: no Messages/Responses dispatch, JSON/SSE/tool/provider logic, fallback, retry, credential storage, conversation persistence, web, desktop, or arbitrary production clients;
- the clean-consumer command/result and exact unblock statement for `genkit-providers-dart`.

Review the response against the canonical request and current README before marking it completed. Request creation or response drafting is not owner acceptance. Do not claim Rook production adoption; Rook remains the intended downstream consumer.

## Rollback and recovery

- Before publication, revert or correct the release commit normally and rerun all affected gates. Do not create or move the version tag until the candidate is accepted.
- If local tag verification or tag push differs from the published commit, stop. Delete or move an unpublished local tag only through an explicit maintainer correction; never retag an already published version.
- If publication fails transiently before pub.dev accepts the version, preserve the clean untagged commit, fix authorization/service issues, and rerun validation before another operator-invoked upload.
- If publication fails terminally because ownership is unavailable, the package name is claimed in the recheck/upload race, or pub.dev rejects the identity, create no tag or GitHub release. Matt explicitly chooses a new name/version, revises the plan/request/downstream contract, and commits that correction normally.
- If an external workflow nevertheless pushed a tag or created a draft GitHub release before pub.dev acceptance, first prove the version was never hosted. With explicit maintainer approval, delete only that unpublished remote tag and draft release, record the cleanup, and then revise package identity. Never delete or move a tag for a hosted version.
- After pub.dev accepts `0.1.0`, it is immutable. A defect requires a new reviewed patch version and a corrected response. Do not overwrite or silently reinterpret `0.1.0`.
- If a consumer has pinned the bad release, rollback occurs by changing the consumer pin to another hosted version. This library owns no stored data or configuration migration.
- If any live or device gate becomes unavailable after code completion, leave the request open with the exact missing gate; do not publish an incomplete unblock response.

## Acceptance criteria

- The clean release commit, tag, pub.dev version, hosted content hash, and response all identify the same source.
- Pub.dev resolves `opencode_auth` `0.1.0`, and a fresh consumer proves hosted-only resolution with no overrides.
- The response contains every acceptance item from the canonical request and no secret or sensitive runtime evidence.
- `genkit-providers-dart` can implement its pre-dispatch enum check without importing a `src/` path or parsing text.
- The response accurately distinguishes completed auth-package work from downstream provider/Rook work.
