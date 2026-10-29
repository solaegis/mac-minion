# Security

Please report a security problem privately, not in a public issue: use **Report a vulnerability** on this repository's [Security tab](https://github.com/solaegis/mac-minion/security/advisories/new).

Things that matter most in MacMinion:

- Addon zips it downloads and unpacks into your AddOns folder
- The Sparkle update feed and its EdDSA signatures
- API keys for Claude and OpenAI in the Keychain
- The `macminion` command line

Only the latest release gets fixes.
