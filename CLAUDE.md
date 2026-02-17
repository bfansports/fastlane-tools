# fastlane-tools

## What This Is

Shared Fastlane utility library for bFAN Sports iOS and Android build automation. Provides reusable Ruby functions imported by mobile app Fastfiles for CI/CD workflows including version management, deployment to App Store/Play Store, Slack notifications, AWS integrations (SSM, S3, DynamoDB), and organization-specific configuration loading.

## Tech Stack

- **Build Automation**: Fastlane (Ruby-based)
- **Languages**: Ruby
- **AWS SDK**: aws-sdk-ssm, aws-sdk-s3, aws-sdk-dynamodb
- **Dependencies**: fastlane, active_support, net/http (Slack API)
- **Configuration**: YAML (iOS), JSON (Android service accounts)
- **Version Control**: Git tag-based versioning

## Quick Start

```bash
# Install dependencies
bundle install

# Tag a new version for release
git tag -a 1.0.0 -m "version 1.0.0"
git push origin 1.0.0

# Import in mobile app Fastfile
import_from_git(
  url: 'git@github.com:bfansports/fastlane-tools.git',
  branch: 'master',
  path: 'bFANTools.rb'
)
```

<!-- Ask: What Ruby version is required? Is there a .ruby-version file? -->
<!-- Ask: Are there automated tests for these functions? -->
<!-- Ask: How are changes tested before tagging a release? -->

## Project Structure

```
fastlane-tools/
├── bFANTools.rb              # Main utility library (AWS, versioning, config loading)
├── export_translations.rb    # Translation export script
├── Gemfile                   # Ruby dependencies
├── .rubocop.yml              # Linting configuration (extends .rubocop.fastlane.yml)
└── README.md                 # Versioning and contribution guidelines
```

## Dependencies

**Internal bFAN repos:**
- Imported by iOS app repos (SA-User-MobileApp-iOS, SA-Admin-MobileApp-iOS)
- Imported by Android app repos (SA-User-WhiteLabelApps-Android, BFanSSO-Android)

**External services:**
- AWS Systems Manager (Parameter Store) — version code storage
- AWS S3 — credential storage, artifact uploads
- AWS DynamoDB — version tracking
- Slack API — build notifications
- Google Play Console API — Android version management
- App Store Connect API — iOS version management

**Ruby Gems:**
- fastlane
- aws-sdk-ssm, aws-sdk-s3, aws-sdk-dynamodb
- activesupport

## API / Interface

**Key Functions in bFANTools.rb:**

- `loadAndroidConfigFile(org_id)` — Load organization-specific Google Play service account JSON
- `loadIOSConfigFile(org_id)` — Load organization-specific iOS Fastlane environment YAML
- `getVersionCode(org_id, track)` — Fetch and increment Android version code from Play Store or AWS SSM
- `writeVersionCode(org_id, track, versionCode)` — Persist version code to AWS SSM Parameter Store
- `resetIOSRepo()` — Reset modified Info.plist files after build
- Slack notification helpers (SLACK_API_URL, SLACK_OAUTH_TOKEN)

**Import Pattern (used by mobile repos):**
```ruby
import_from_git(
  url: 'git@github.com:bfansports/fastlane-tools.git',
  branch: 'master',  # or specific tag like 'v1.2.3'
  path: 'bFANTools.rb'
)
```

## Key Patterns

- **Semantic Versioning**: Git tags follow semver (MAJOR.MINOR.PATCH)
- **Tagged Releases**: import_from_git caching requires tagged versions
- **Organization Overrides**: Falls back to generic configs if org-specific files missing
  - Android: `json_keys/<org_id>-api.json` → `json_keys/generic-api.json`
  - iOS: `FastlaneEnv/<org_id>.yaml` → `FastlaneEnv/generic.yaml`
- **AWS SSM for Version Codes**: Replaces legacy S3-based version storage
- **Slack Integration**: Build status notifications via OAuth token

## Environment

**Required Environment Variables:**
- `SLACK_OAUTH_TOKEN` — For build notifications

**AWS Credentials:**
- Must have permissions for:
  - SSM Parameter Store (read/write)
  - S3 (read/write to credential buckets)
  - DynamoDB (optional, for version tracking)

**File Structure (when imported by mobile repos):**
- `json_keys/<org_id>-api.json` — Android service account credentials
- `FastlaneEnv/<org_id>.yaml` — iOS build configurations

## Deployment

**Release Process:**
1. Make changes to bFANTools.rb or export_translations.rb
2. Test locally by importing into a mobile repo Fastfile
3. Update README if adding new functions
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

**Manual Testing:**
- Import unreleased branch in mobile repo Fastfile
- Run Fastlane lanes (build, deploy, test)
- Verify AWS SSM, Slack, Play Store interactions

**Linting:**
```bash
bundle exec rubocop
```

## Gotchas

- **Caching**: Fastlane caches imported Git repos; change branch/tag or clear cache to pick up changes
- **AWS Credentials**: Requires AWS CLI configured with appropriate profile and permissions
- **Version Code Migration**: Legacy code shows S3-based version storage (commented out); now uses SSM
- **Slack Token Expiry**: SLACK_OAUTH_TOKEN must be refreshed if Slack app credentials change
- **JSON Key Paths**: Relative paths assume execution from mobile repo root; adjust if running from subdirectories
- **Organization ID Convention**: Must match DynamoDB/SSM naming convention (lowercase, no spaces)
- **Semantic Versioning**: Breaking changes require MAJOR version bump; mobile repos must update imports
- **Tag Immutability**: Never delete or re-tag versions; create new version instead