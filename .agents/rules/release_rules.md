# Release & Versioning Policy for Astra

## Core Rules:
1. **User Approval Required for Releases**:
   - Never generate, delete, or push a release tag (`v*`) or release build unless the USER explicitly requests: e.g., *"release v1.0.0"*, *"is version ko release kar do"*, *"beta release bana do"*.
   - Do NOT automatically tag or trigger releases on normal feature commits or bug fixes.

2. **Web / Docs (`docs/index.html`) Deployment**:
   - **Do NOT touch or deploy `docs/**` on release runs.** User handles web hub deployments separately.
   - When user asks to release, run **ONLY** the build release flow (3rd screenshot - `build.yml` triggered via Git Tag push or workflow dispatch).
   - Never trigger or force `deploy-pages.yml` during mobile app release.

3. **Accurate Release Notes & Changelog**:
   - Every release MUST document exact, detailed changelog of:
     - **🚀 What's New:** Precise feature additions and improvements.
     - **🐛 Bug Fixes & Issues Resolved:** Exact bugs resolved, edge cases handled, and performance optimizations.
   - Pass this changelog into `.github/scripts/publish_release.sh` or the release commit/tag message so GitHub Releases shows the real changelog instead of placeholder text.

4. **User-Specified Versioning**:
   - Always use the exact version name provided by the USER (e.g. `v1.0.1`, `v1.0.2-beta`, `v1.1.0-dev`).
   - Tags with `-beta`, `-alpha`, `-dev` -> Beta / Pre-release.
   - Standard semantic tags (e.g. `v1.0.4`) -> Stable Release.

5. **Release Execution Steps When Requested**:
   - Ensure working tree is clean and `flutter analyze` has 0 compilation errors.
   - Update `pubspec.yaml` version code and build number.
   - Stage and commit app files only (NO `docs/**`): `git commit -m "feat: release <version> - <summary>"`.
   - Create tag: `git tag -a <version> -m "<detailed notes>"`.
   - Push release tag to remote: `git push origin <version>`.
