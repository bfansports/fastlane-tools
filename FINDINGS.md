# Security Audit Findings — fastlane-tools

**Date:** 2026-02-17
**Auditor:** DevOps Engineer (AI-assisted)
**Repo:** bfansports/fastlane-tools
**Branch:** master
**Scope:** bFANTools.rb, export_translations.rb, CI/CD config, credential management

---

## Critical

### C-1: Shell Injection via Unsanitized User Input in Backtick Commands

**File:** `bFANTools.rb` lines 210-246, 256, 315, 526

Multiple functions interpolate parameters directly into backtick shell commands without any sanitization:

```ruby
# hotfixstart/hotfixfinish — tag param goes straight into shell
`git checkout -b fastlane/#{tag} master`
`git merge --no-ff -m "[skip ci] [fastlane] images_updates #{tag}" fastlane/#{tag}`
`git tag -a #{tag} -m "[fastlane] Tag: #{tag}"`
`git push origin #{tag}`

# mkdir with unsanitized folder path
`mkdir -p #{folder}`

# createKeystore — org param goes into shell
keystore = `#{pwd}/keystore_generator.sh #{org}`
```

If `tag`, `folder`, or `org` contain shell metacharacters (`;`, `|`, `$()`, etc.), arbitrary commands execute. While these values typically come from CI parameters or Fastlane options (not direct end-user input), a compromised CI config or careless invocation could exploit this.

**Impact:** Remote code execution on build machines.

**Recommendation:**
- Replace backtick commands with `Fastlane::Actions.sh()` or `Open3.capture3()` which handle argument escaping.
- Use `Shellwords.escape()` for any interpolated values.
- For `mkdir`, use `FileUtils.mkdir_p(folder)` (Ruby stdlib, no shell).

---

### C-2: Firebase Service Account Key Written to Disk Unprotected

**File:** `bFANTools.rb` lines 1300-1316

```ruby
def set_firebase_credentials(org_id: String, firebase_project_id: String)
  # ...
  service_account_key = ssm_response.parameter.value
  service_account_key_file = File.expand_path("firebase_service_account_key.json")
  File.write(service_account_key_file, service_account_key)
  ENV["GOOGLE_APPLICATION_CREDENTIALS"] = service_account_key_file
```

Problems:
1. **Predictable filename** in the working directory — any process can read it.
2. **No file permissions restriction** — created with default umask (typically 0644, world-readable).
3. **Never cleaned up** — the file persists after the build, potentially across builds on shared CI runners.
4. **Contains full GCP service account private key** pulled from SSM with decryption.

**Impact:** Credential exposure on shared build infrastructure. A subsequent or parallel build could read the key.

**Recommendation:**
- Use `Tempfile` with a random name: `Tempfile.new(['firebase_sa_', '.json'])`.
- Set restrictive permissions: `File.chmod(0600, path)`.
- Add an `ensure` block to delete the file after use.
- Add the pattern `firebase_service_account_key.json` to `.gitignore`.

---

## High

### H-1: No .gitignore File — Credentials at Risk of Accidental Commit

**File:** Repository root (missing)

The repo has **no `.gitignore` file**. Given that:
- `set_firebase_credentials` writes `firebase_service_account_key.json` to the working directory
- Android config files reference `json_keys/*.json` (Google Play service account keys)
- S3 downloads go to `/tmp/` (not in repo, but changelog writes to `./tmp/changelog.txt`)

Any developer or CI job that runs these tools from the repo directory could accidentally commit credentials.

**Impact:** Credential leak via Git history.

**Recommendation:** Create `.gitignore` with at minimum:
```
firebase_service_account_key.json
*.json.bak
tmp/
.env
*.p12
*.mobileprovision
```

---

### H-2: Hardcoded S3 Bucket Name for Production Credentials

**File:** `bFANTools.rb` lines 152-157, 163-168, 193-198

The bucket `sportarchive-prod-creds` is hardcoded in three functions:

```ruby
def writeVersionCode(file, versionCode)
  s3 = Aws::S3::Client.new(region: 'us-east-1')
  obj = s3.put_object({ bucket: "sportarchive-prod-creds", ... })
end
```

Also hardcoded in `getTestersList` and `getiPhonesList`.

Problems:
1. Cannot differentiate dev/qa/prod environments — always hits prod bucket.
2. Bucket name leaked in source code (minor, but against least-privilege principle).
3. The `writeVersionCode` function is a legacy S3 writer still active (not just commented out like the reader).

**Impact:** Accidental writes to production credential bucket from non-prod environments.

**Recommendation:**
- Extract bucket name to environment variable: `ENV.fetch('BFAN_CREDS_BUCKET', 'sportarchive-prod-creds')`.
- Consider whether `writeVersionCode` (S3-based) is still used or should be removed alongside the commented-out reader.

---

### H-3: Sensitive Data Written to /tmp Without Cleanup

**File:** `bFANTools.rb` lines 169, 175, 199, 205

```ruby
# getTestersList
obj = s3.get_object({ bucket: "sportarchive-prod-creds", key: 'bfan_testers_list.txt' },
                    target: '/tmp/bfan_testers_list.txt')
testers = File.read('/tmp/bfan_testers_list.txt').split(",")

# getiPhonesList
obj = s3.get_object({ bucket: "sportarchive-prod-creds", key: 'bfan_iphones_list.json' },
                    target: '/tmp/bfan_iphones_list.json')
```

Tester email addresses and device identifiers are written to world-readable `/tmp` files and never cleaned up. On shared CI runners, these persist between builds.

**Impact:** PII (tester emails) and device data exposure on shared infrastructure.

**Recommendation:**
- Use `Tempfile` or `StringIO` instead of writing to disk.
- For `get_object`, use `response.body.read` directly instead of `target:` file parameter.
- If files must be written, use `ensure` blocks to clean up.

---

### H-4: URI.open (open-uri) Used with URLs from Database — SSRF Risk

**File:** `bFANTools.rb` lines 15, 271-325

```ruby
require 'open-uri'
# ...
File.binwrite("#{folder}/splash_image.jpg", URI.open(org['branding']['splash_screen']).read)
```

`URI.open` (from `open-uri`) fetches arbitrary URLs stored in the DynamoDB `Organizations` table. If an attacker can modify organization branding URLs (via admin panel compromise or direct DB access), they can:
1. Trigger SSRF to internal AWS metadata endpoint (`http://169.254.169.254/...`)
2. Exfiltrate IAM role credentials from the build machine
3. Fetch malicious payloads written to the local filesystem

`open-uri` also supports `file://` protocol in older Ruby versions.

**Impact:** Server-Side Request Forgery leading to credential theft or internal network scanning.

**Recommendation:**
- Validate URLs against an allowlist of domains (e.g., `*.s3.amazonaws.com`, known CDN domains).
- Use `Net::HTTP` with explicit URL parsing and scheme validation (only `https:`).
- Block `file://`, `ftp://`, and private IP ranges.

---

## Medium

### M-1: GitHub Actions Workflow Uses Outdated action/checkout@v2

**File:** `.github/workflows/github-backup.yml` line 10

```yaml
- uses: actions/checkout@v2
```

`actions/checkout@v2` uses Node.js 12 (EOL) and is vulnerable to known supply chain issues. It also uses the deprecated `set-output` command.

**Impact:** Supply chain risk; potential for compromised action execution.

**Recommendation:** Update to `actions/checkout@v4`.

---

### M-2: GitHub Actions Workflow Triggers on Wrong Branch

**File:** `.github/workflows/github-backup.yml` line 5

```yaml
on:
  push:
    branches:
      - develop
```

The repo's default/primary branch is `master` (per README and all git operations in the code). The backup workflow triggers on `develop` which may not exist or receive pushes, meaning **backups may never run**.

**Impact:** No S3 backups of the repository despite the workflow existing.

**Recommendation:** Change trigger to `master` or add both `master` and `develop`.

---

### M-3: Force Push Enabled by Default in pushToGitRemotes

**File:** `bFANTools.rb` lines 419-431

```ruby
def pushToGitRemotes(branch = 'develop', force = 0)
  if force        # BUG: 0 is truthy in Ruby!
    force = "-f"
  else
    force = ""
  end
```

In Ruby, `0` is truthy. So `pushToGitRemotes('develop', 0)` — the default — will set `force = "-f"`, meaning **every call with default arguments force-pushes**. The only call site (`afterAll`) passes `1`, which also force-pushes.

This means `pushToGitRemotes` **always force-pushes** regardless of the `force` parameter value.

**Impact:** Accidental history rewriting on remote branches; potential code loss.

**Recommendation:** Fix the truthiness check:
```ruby
def pushToGitRemotes(branch = 'develop', force: false)
  force_flag = force ? "-f" : ""
  # ...
end
```

---

### M-4: Slack OAuth Token Loaded at Module Level as Constant

**File:** `bFANTools.rb` lines 9-10

```ruby
SLACK_API_URL = "https://slack.com/api/chat.postMessage"
SLACK_OAUTH_TOKEN = ENV["SLACK_OAUTH_TOKEN"]
```

The token is captured once at require-time into a Ruby constant. Problems:
1. If the env var is set after `import_from_git`, the constant is `nil`.
2. Constants are visible in stack traces, error reports, and `inspect` output.
3. Cannot be rotated without restarting the process.

**Impact:** Token visibility in error output; inflexible token management.

**Recommendation:** Use `ENV["SLACK_OAUTH_TOKEN"]` directly at call sites, or wrap in a method.

---

### M-5: DynamoDB Region Falls Back to nil in Some Functions

**File:** `bFANTools.rb` — multiple functions

Inconsistent region handling across DynamoDB client creation:

```ruby
# Some functions — nil fallback (will use SDK default chain)
Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", nil))

# Other functions — explicit eu-west-1 fallback
Aws::DynamoDB::Client.new(region: ENV.fetch("AWS_DEFAULT_REGION", "eu-west-1"))

# S3 — hardcoded us-east-1
Aws::S3::Client.new(region: 'us-east-1')

# SSM — no region specified at all
Aws::SSM::Client.new
```

This inconsistency means functions may hit different regions depending on environment config, causing silent data splits or failures.

**Impact:** Data read from wrong region; hard-to-debug production issues.

**Recommendation:** Standardize region resolution. Use a single helper:
```ruby
def aws_region
  ENV.fetch('AWS_DEFAULT_REGION', 'eu-west-1')
end
```

---

### M-6: Debug Print Statement Left in Production Code

**File:** `bFANTools.rb` line 615

```ruby
UI.important("This is a test print from Chase")
```

Developer debug statement left in `updateAppBetaVersion`. Exposes developer name and signals insufficient code review.

**Impact:** Unprofessional log output; indicator of incomplete review process.

**Recommendation:** Remove the debug line.

---

### M-7: gitCommit Function Vulnerable to Injection via msg Parameter

**File:** `bFANTools.rb` lines 444-446

```ruby
def gitCommit(file, msg)
  sh("git diff-index --quiet HEAD -- #{file} || git commit #{file} -m '#{msg}'")
end
```

Both `file` and `msg` are interpolated into a shell command. A message containing a single quote (`'`) breaks the command; a crafted message could inject arbitrary shell commands.

**Impact:** Shell injection if msg contains quotes or shell metacharacters.

**Recommendation:** Use `Shellwords.escape()` for both parameters, or use Fastlane's built-in `git_commit` action.

---

## Low

### L-1: Commented-Out Code (Legacy S3 Version Reader)

**File:** `bFANTools.rb` lines 26-50

Large block of commented-out code for the old S3-based version code reader. Meanwhile, `writeVersionCode` (line 151) still uses S3 actively — the reader was migrated to Google Play API but the writer was not.

**Impact:** Code confusion; possible orphaned S3 writes that nothing reads.

**Recommendation:** If the S3 writer is truly unused, remove both the commented reader and the active writer. If still needed, document why.

---

### L-2: No Automated Tests

No test files exist in the repository. Rubocop linting is configured but there are no RSpec, Minitest, or other test files.

**Impact:** Regressions go undetected; security fixes cannot be verified.

**Recommendation:** Add at minimum:
- Unit tests for `getVersionCode`, `loadAndroidConfigFile`, `loadIOSConfigFile`
- Integration test stubs for AWS interactions (using mocks)
- A CI workflow that runs rubocop + tests on PRs

---

### L-3: loadIOSConfigFile Has Path Construction Bug

**File:** `bFANTools.rb` line 73

```ruby
if File.file?("#{path}./FastlaneEnv/#{org_id}.yaml")
```

The `./` after `path` creates paths like `./fastlane/./FastlaneEnv/org.yaml` or `./FastlaneEnv/org.yaml`. While this works due to filesystem path normalization, it's fragile and confusing.

**Impact:** Potential file-not-found on strict filesystems; code maintainability.

**Recommendation:** Use `File.join(path, 'FastlaneEnv', "#{org_id}.yaml")` for proper path construction.

---

### L-4: resetIOSRepo Function is Empty

**File:** `bFANTools.rb` lines 85-87

```ruby
def resetIOSRepo
  # sh "git checkout -q ..."
end
```

The function body is entirely commented out. It's called from consuming repos' Fastfiles but does nothing.

**Impact:** Modified Info.plist files are not reset after builds, potentially causing dirty working trees.

**Recommendation:** Either implement the function or remove it and update callers.

---

### L-5: Gemfile.lock Pinned to Specific Platforms Only

**File:** `Gemfile.lock` lines 311-316

```
PLATFORMS
  arm64-darwin-22
  arm64-darwin-23
  x86_64-darwin-21
  x86_64-darwin-22
  x86_64-linux
```

Missing `arm64-darwin-24` (macOS Sequoia) and newer. CI runners or developer machines on newer macOS versions may need to `bundle lock --add-platform`.

**Impact:** Build failures on newer macOS versions.

**Recommendation:** Run `bundle lock --add-platform` for current CI runner platforms, or use platform-agnostic lockfile strategy.

---

## Agent Skill Improvements

1. **CLAUDE.md enriched** — Lane inventory, credential flow documentation, function catalog, and CI integration notes added (see companion CLAUDE.md update).
2. **Missing `get_firebase_project_id`** — This function is called three times in bFANTools.rb but is not defined here. It must be provided by consuming Fastfiles. Document this as an external dependency.
3. **Knowledge gaps captured** — Several `<!-- Ask: ... -->` placeholders in the existing CLAUDE.md remain unanswered. These should be pursued in future sessions with team members.

---

## Positive Observations

1. **SSM for Firebase credentials** — The `set_firebase_credentials` function correctly uses AWS SSM Parameter Store with decryption for GCP service account keys, which is the right approach. The implementation just needs cleanup (tempfiles, permissions, cleanup).
2. **YAML.safe_load used** — iOS config loading uses `YAML.safe_load` (line 77), preventing YAML deserialization attacks. Good.
3. **Semantic versioning enforced** — Tag-based releases with semver convention and `import_from_git` caching provide version stability.
4. **DynamoDB operations are well-structured** — Defensive initialization (`if_not_exists`) in multiple update functions prevents crashes on incomplete org data.
5. **Error handling is present** — Most AWS operations have rescue blocks with meaningful error messages via `UI.error`.
6. **Rubocop configured** — Linting is set up with fastlane-specific rules, even if not enforced in CI.
7. **Environment-aware** — `getEnvVar` validates the `ENV` variable contains expected values before proceeding.
