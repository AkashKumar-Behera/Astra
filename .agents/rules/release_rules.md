# Release & Versioning Policy for Astra

## Core Rules:
1. **User Approval Required for Releases**:
   - Never generate, delete, or push a release tag (`v*`) or release build unless the USER explicitly requests: e.g., *"release v1.0.0"*, *"is version ko release kar do"*, *"beta release bana do"*.
   - Do NOT automatically tag or trigger releases on normal feature commits or bug fixes.

2. **User-Specified Versioning**:
   - Always use the exact version name provided by the USER (e.g. `v1.0.1`, `v1.0.2-beta`, `v1.1.0-dev`).
   - If the USER does not specify whether it is stable or beta, ask or follow the tag convention:
     - Tags with `-beta`, `-alpha`, `-dev` -> Beta / Pre-release
     - Standard semantic tags (e.g. `v1.0.1`) -> Stable Release

3. **Release Execution Steps When Requested**:
   - Ensure working tree is clean and `flutter analyze` has 0 compilation errors.
   - Stage and commit any pending changes with a descriptive message.
   - Create annotated git tag with changelog: `git tag -a <version> -m "<notes>"`.
   - Push to remote: `git push origin main --tags`.
