# fastlane-tools

## What This Is

Shared Fastlane utility library for bFAN Sports iOS and Android build automation. Provides reusable Ruby functions imported by mobile app Fastfiles for CI/CD workflows including version management, deployment to App Store/Play Store, Slack notifications, AWS integrations (SSM, S3, DynamoDB), and organization-specific configuration loading.

## Tech Stack

- **Build Automation**: Fastlane (Ruby-based)
- **Languages**: Ruby
- **AWS SDK**: aws-sdk-ssm, aws-sdk-s3, aws-sdk-dynamodb
- **Dependencies**: fastlane, active_support, net/http (Slack API), open-uri
- **Configuration**: YAML (iOS via `FastlaneEnv/`), JSON (Android via `json_keys/`)
- **Version Control**: Git tag-based versioning (semver)
- **Target Ruby**: 2.7.3 (per .rubocop.fastlane.yml)

## Quick Start

```bash
# Install dependencies
bundle install

# Run linter
bundle exec rubocop

# Tag a new version for release
git tag -a 1.0.0 -m "version 1.0.0"
git push origin 1.0.0

# Import in mobile app Fastfile
import_from_git(
  url: 'git@github.com:bfansports/fastlane-tools.git',
  branch: 'master',  # or specific tag
  path: 'bFANTools.rb'
)
```

<!-- Ask: What Ruby version is required? Is there a .ruby-version file? -->
<!-- Ask: Are there automated tests for these functions? -->
<!-- Ask: How are changes tested before tagging a release? -->

## Project Structure

```
fastlane-tools/
├── bFANTools.rb              # Main utility library (~1400 lines)
├── export_translations.rb    # Translation export from DynamoDB to iOS/Android string files
├── Gemfile                   # Ruby dependencies
├── Gemfile.lock              # Pinned dependency versions
├── .rubocop.yml              # Linting config (extends .rubocop.fastlane.yml)
├── .rubocop.fastlane.yml     # Fastlane-specific rubocop rules
├── .github/workflows/
│   └── github-backup.yml     # S3 mirror backup (triggers on develop — may be wrong branch)
└── README.md                 # Versioning and contribution guidelines
```

## Dependencies

**Internal bFAN repos (consumers):**
- SA-User-MobileApp-iOS — iOS user app
- SA-Admin-MobileApp-iOS — iOS admin app
- SA-User-WhiteLabelApps-Android — Android user app
- BFanSSO-Android — Android SSO app

**External services:**
- AWS Systems Manager (Parameter Store) — Firebase service account keys, version codes
- AWS S3 (`sportarchive-prod-creds` bucket) — version codes (legacy), tester lists, device lists
- AWS DynamoDB (`Organizations` table) — org configs, app flags, ratings, store versions
- AWS DynamoDB (`AppStringsTranslations`, `Languages` tables) — translation export
- Slack API — build notifications (via OAuth token and webhook URL)
- Google Play Console API — Android version code management
- App Store Connect API — iOS version management
- Firebase Hosting — dynamic links deployment

**Ruby Gems:** fastlane, aws-sdk-ssm, aws-sdk-s3, aws-sdk-dynamodb, activesupport, htmlentities (export_translations.rb uses nokogiri indirectly)

## Lane Inventory

### Defined Lanes (in bFANTools.rb)

| Lane | Description | Key Parameters |
|------|-------------|----------------|
| `deploy_firebase_hosting` | Deploy Firebase Hosting config for dynamic links | `orgs:`, `all:`, `dry_run:` |
| `update_firebase_project_id` | Update org's firebase_project_id in DynamoDB | `org_id:`, `firebase_project_id:` |
| `test_september_2024` | Test lane (no-op) | none |

### Utility Functions (not lanes — called from consuming Fastfiles)

**Configuration Loading:**
- `loadAndroidConfigFile(org_id)` — Resolve org-specific or generic Google Play JSON key path
- `loadIOSConfigFile(org_id)` — Load org-specific or generic iOS YAML config
- `getTeamId(org_id)` — Get Apple Developer Team ID from iOS config
- `getTeamName(org_id)` — Get Apple Developer Team Name from iOS config
- `getMatchGitBranch(org_id)` — Get Fastlane Match git branch from iOS config
- `getEnvVar` — Parse and validate `ENV` environment variable (dev/qa/prod)

**Version Management:**
- `getVersionCode(org_id, track)` — Get next Android version code from Play Store (with beta/prod logic)
- `writeVersionCode(file, versionCode)` — Write version code to S3 (legacy)
- `getNextTagVersion` — Calculate next semver tag from git tags
- `getPastGitTag(back)` — Get Nth most recent semver tag
- `getTagCommitId(tag)` — Resolve tag to commit SHA

**Organization Data (DynamoDB):**
- `getOrg(org_id)` — Fetch single org record
- `getActiveOrgs` — Get all public active orgs
- `getInStoreOrgs` — Get all orgs with apps in stores
- `updateAppFlag(org_id, type, env, value)` — Update app active flag
- `updateAppBetaVersion(org_id, type, env, version)` — Update beta version info
- `updateAppProdVersion(org_id, app_type, version)` — Update production version info
- `updateAppInReviewVersion(org_id, app_type, version)` — Update in-review version info
- `updateAppStoreState(org_id, type, version)` — Update store state
- `updateAppStoreRatings(org_id, type, ratings)` — Update app ratings
- `dynamodb_full_scan(dynamodb, scan_opts)` — Paginated DynamoDB scan helper

**Build Assets:**
- `downloadOrgImages(org_id, folder, asset_path)` — Download org branding images
- `downloadOrgAppIcon(org_id, folder)` — Download org app icons only
- `createKeystore(org)` — Generate Android keystore via shell script
- `createAndroidChangeLogFile(versionCode, org, release_notes)` — Create Play Store changelog
- `createiOSChangeLogFile(org, release_notes, path)` — Create App Store changelog

**Git Operations:**
- `hotfixstart(tag)` — Create hotfix branch from master
- `hotfixfinish(tag)` — Merge hotfix into master and develop, tag
- `tagpush(tag)` — Push master, develop, and tag to origin
- `pushToGitRemotes(branch, force)` — Push to all remotes (WARNING: force-push bug — see Gotchas)
- `pullFromGitRemotes(branch)` — Pull from all remotes
- `gitCommit(file, msg)` — Commit specific file if changed
- `getMainGitRemote` — Detect upstream vs origin
- `getLastCommit` — Get HEAD SHA
- `getLastGitRemote` — Get last configured remote
- `getPastTagLogs(past1, past2, filter)` — Get commit log between tags
- `beforeAll(tag)` — Pre-build git setup (fetch, checkout)
- `afterAll(tag, env)` — Post-build git tag update

**Notifications:**
- `notifySlack(msg, payload, success, channel)` — Send build notification via Slack webhook
- `notifySlackClient(msg, org_id)` — Send notification to org-specific Slack channel via OAuth API

**Firebase:**
- `set_firebase_credentials(org_id:, firebase_project_id:)` — Fetch GCP service account from SSM, write to disk, set env var

**Testing:**
- `getTestersList(org_id)` — Fetch tester emails from S3 + org-specific testers from DynamoDB
- `getiPhonesList` — Fetch registered test devices from S3
- `register_app(apk, bundle_id, env)` — Register app in Crashlytics via emulator
- `getAvdEmulator` — Get first available Android emulator AVD

**External dependency (NOT defined here):**
- `get_firebase_project_id(org_id)` — Must be provided by the consuming Fastfile

## Credential Management

### Credential Flow

| Credential | Source | Storage | Access Method |
|-----------|--------|---------|---------------|
| Google Play service account JSON | `json_keys/<org_id>-api.json` | Git (consuming repo) | `loadAndroidConfigFile()` reads from filesystem |
| iOS Fastlane config (team_id, etc.) | `FastlaneEnv/<org_id>.yaml` | Git (consuming repo) | `loadIOSConfigFile()` reads YAML |
| Firebase GCP service account key | AWS SSM Parameter Store | SSM (encrypted) | `set_firebase_credentials()` decrypts and writes to local file |
| Slack OAuth token | `SLACK_OAUTH_TOKEN` env var | Environment | Read at module load time into constant |
| Slack webhook URL | `SLACK_BFAN_URL` env var | Environment | Read at call time |
| AWS credentials | AWS credential chain | Environment/profile | SDK default resolution |
| Tester email list | S3 `sportarchive-prod-creds` | S3 bucket | Downloaded to `/tmp/` |
| Test device list | S3 `sportarchive-prod-creds` | S3 bucket | Downloaded to `/tmp/` |
| GitHub backup keys | GitHub Actions secrets | `AWS_ACCESS_KEY`, `AWS_SECRET_KEY` | Injected by Actions |

### Required Environment Variables

| Variable | Used By | Required? |
|----------|---------|----------|
| `SLACK_OAUTH_TOKEN` | `notifySlackClient` | For client notifications |
| `SLACK_BFAN_URL` | `notifySlack` | For team build notifications |
| `AWS_DEFAULT_REGION` | DynamoDB operations | Yes (inconsistent fallback — some use `nil`, some use `eu-west-1`) |
| `ENV` | `getEnvVar` | Yes (must contain dev/qa/prod) |
| `BITRISE_BUILD_URL` | `notifySlack` | Optional (CI context) |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase tools | Set by `set_firebase_credentials()` |

## CI Integration

### How This Repo Is Consumed

Mobile repos import this library via Fastlane's `import_from_git`:
```ruby
import_from_git(
  url: 'git@github.com:bfansports/fastlane-tools.git',
  branch: 'master',  # or pinned tag like '1.2.3'
  path: 'bFANTools.rb'
)
```

Fastlane caches the imported repo. Changing the tag/branch or clearing the cache forces re-download.

### CI Platforms
- **Bitrise** — Primary CI (detected via `BITRISE_BUILD_URL` env var)
- **GitHub Actions** — S3 backup workflow only

### GitHub Actions Workflow
- `github-backup.yml` — Mirrors repo to S3 bucket `bfansports-github-backup/fastlane-tools`
- Uses `peter-evans/s3-backup@v1` with AWS credentials from repository secrets
- **Note:** Currently triggers on `develop` branch, but repo uses `master` as primary — may not be running

## Key Patterns

- **Semantic Versioning**: Git tags follow semver (MAJOR.MINOR.PATCH)
- **Tagged Releases**: `import_from_git` caching requires tagged versions
- **Organization Overrides**: Falls back to generic configs if org-specific files missing
  - Android: `json_keys/<org_id>-api.json` -> `json_keys/generic-api.json`
  - iOS: `FastlaneEnv/<org_id>.yaml` -> `FastlaneEnv/generic.yaml`
- **AWS SSM for Firebase**: Replaced deprecated `FIREBASE_TOKEN` with SSM-stored service account keys
- **Slack Integration**: Two methods — webhook (team channel) and OAuth API (org-specific channels)
- **DynamoDB Full Scan**: Custom pagination helper for tables exceeding 1MB scan limit

## Environment

### AWS Permissions Required

- **SSM Parameter Store**: `ssm:GetParameter` with decryption on `/google_cloud_ci_cd_service_account_generator/*`
- **S3**: `s3:GetObject`, `s3:PutObject` on `sportarchive-prod-creds` bucket
- **DynamoDB**: `dynamodb:GetItem`, `dynamodb:UpdateItem`, `dynamodb:Scan` on `Organizations` table
- **DynamoDB** (export_translations.rb): `dynamodb:Scan` on `AppStringsTranslations` and `Languages` tables

### File Structure (when imported by mobile repos)

```
mobile-repo/
├── fastlane/
│   ├── Fastfile              # Imports bFANTools.rb
│   ├── json_keys/            # Android: Google Play service account JSONs
│   │   ├── generic-api.json
│   │   └── <org_id>-api.json
│   └── FastlaneEnv/          # iOS: org-specific build configs
│       ├── generic.yaml
│       └── <org_id>.yaml
```

## Deployment

**Release Process:**
1. Make changes to bFANTools.rb or export_translations.rb
2. Run `bundle exec rubocop` to lint
3. Test locally by importing branch into a mobile repo Fastfile
4. Commit changes
5. Tag with semver: `git tag -a X.Y.Z -m "version X.Y.Z"`
6. Push tag: `git push origin X.Y.Z`

**Consuming Repos:**
- Mobile repos pin to specific tags for stability
- Update tag version in mobile repo Fastfiles to adopt new features/fixes

<!-- Ask: Is there a changelog maintained for version history? -->
<!-- Ask: Who approves changes to this shared library? -->
<!-- Ask: Are there breaking change policies? -->

## Testing

<!-- Ask: How are changes tested before tagging? Manual testing in a mobile repo? -->
<!-- Ask: Are there unit tests for Ruby functions? -->
<!-- Ask: Is there a staging/beta tag strategy for testing before stable release? -->

**No automated tests exist.** Testing is manual:
- Import unreleased branch in mobile repo Fastfile
- Run Fastlane lanes (build, deploy, test)
- Verify AWS SSM, Slack, Play Store interactions

**Linting:**
```bash
bundle exec rubocop
```

## Gotchas

- **Caching**: Fastlane caches imported Git repos; change branch/tag or clear cache (`~/Library/Caches/com.fastlane/`) to pick up changes
- **AWS Region inconsistency**: DynamoDB client creation uses different fallbacks across functions — some `nil`, some `'eu-west-1'`. SSM client uses SDK default chain. S3 is hardcoded to `us-east-1`. Always set `AWS_DEFAULT_REGION` explicitly.
- **Force-push bug in `pushToGitRemotes`**: The `force` parameter defaults to `0`, but Ruby treats `0` as truthy — so force-push is ALWAYS enabled. Never call this function expecting a non-force push.
- **`get_firebase_project_id` is external**: Called three times but not defined in this repo. The consuming Fastfile must define it or import it from elsewhere.
- **Firebase key file not cleaned up**: `set_firebase_credentials` writes `firebase_service_account_key.json` to the working directory and never deletes it. On shared CI runners, this is a credential leak risk.
- **Shell injection risk**: Many functions use backtick commands with string interpolation (`tag`, `folder`, `org` parameters). Avoid passing untrusted values.
- **S3 bucket hardcoded**: `sportarchive-prod-creds` is hardcoded in three functions. Cannot switch to dev/qa buckets without code changes.
- **Slack token loaded at require-time**: `SLACK_OAUTH_TOKEN` is captured into a constant when the file is required. Set the env var before importing.
- **Version Code Migration**: Legacy S3-based version storage coexists with Play Store API approach. `writeVersionCode` still writes to S3 but the corresponding reader is commented out.
- **Slack Token Expiry**: `SLACK_OAUTH_TOKEN` must be refreshed if Slack app credentials change
- **JSON Key Paths**: Relative paths assume execution from mobile repo root; adjust if running from subdirectories
- **Organization ID Convention**: Must match DynamoDB/SSM naming convention (lowercase, no spaces)
- **Semantic Versioning**: Breaking changes require MAJOR version bump; mobile repos must update imports
- **Tag Immutability**: Never delete or re-tag versions; create new version instead
- **export_translations.rb**: Standalone script — requires `AWS_REGION` env var (not `AWS_DEFAULT_REGION`). Uses `htmlentities` gem (not in Gemfile — may need nokogiri at runtime). Run with: `./export_translations.rb --os=android --path=/path/to/project`
- **Debug statement**: Line 615 has `UI.important("This is a test print from Chase")` — developer debug left in production code
- **No .gitignore**: Repo has no .gitignore file. Credential files written during builds could be accidentally committed.
