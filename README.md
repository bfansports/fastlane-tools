# fastlane-tools

Some Fastlane tools to be used for iOS and Android apps Fastfile CI/CD workflows

## Contributing

When you create a new version, please tag it with:

```bash
git tag -a 1.0.0 -m "version 1.0.0"
git push upstream 1.0.0
```

It makes Fastlane's `import_from_git` caching possible, and adds backwards/forwards compatibility.

This version number should respect [semantic versioning specifications](https://semver.org/).
