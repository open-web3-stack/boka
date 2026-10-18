# Test data and version updates

## Test files

All paths below are relative to `JAMTests/`.

| Data path | Purpose | Test path |
| --- | --- | --- |
| `jamtestvectors/stf/` | Safrole, reports, assurances, accumulation and other state transitions | `Tests/JAMTests/w3f/` |
| `jamtestvectors/codec/`, `jamtestvectors/trie/`, `jamtestvectors/erasure/`, `jamtestvectors/shuffle/` | Encoding and primitives | `Tests/JAMTests/w3f/` |
| `jamtestvectors/traces/` | Full block import, including `fuzzy` and `fuzzy_light` | `Tests/JAMTests/jamtestnet/PolkajamTests.swift` |
| `fuzz/<gp-version>/<case>/` | Block import on fuzz-generated cases, checking the resulting state or rejection | `Tests/JAMTests/jamtestnet/FuzzTests.swift` |
| `javajam/` | Javajam STF and erasure coding | `Tests/JAMTests/jamtestnet/JavajamTests.swift` |
| `jamduna/` | Jamduna traces | `Tests/JAMTests/jamtestnet/JamdunaTests.swift` |
| `fuzz/crypto/ed25519/` | Crypto edge cases | `Tests/JAMTests/crypto/Ed25519Tests.swift` |

`jamtestvectors/traces/` comes from **davxy/jam-test-vectors**, including its `fuzzy` suites. `fuzz/` contains separate cases copied from **davxy/jam-conformance** or local fuzz runs. Updating the submodule does not update `fuzz/`.

The Swift loader uses `.w3f` for `jamtestvectors/` and `.fuzz` for `fuzz/`.

## Update released vectors

Source: [davxy/jam-test-vectors](https://github.com/davxy/jam-test-vectors).

Run from the boka root:

```sh
git submodule sync -- JAMTests/jamtestvectors
git -C JAMTests/jamtestvectors fetch origin <tag-or-commit>
git -C JAMTests/jamtestvectors switch --detach FETCH_HEAD
```

Replace `<tag-or-commit>` with a release tag or a chosen upstream commit SHA.

## Update copied fuzz cases

Source: [davxy/jam-conformance](https://github.com/davxy/jam-conformance).

1. Fetch jam-conformance separately and find cases for the target GP version.
2. Copy the selected case directories unchanged, including available parent/genesis steps and JSON files:

   ```text
   jam-conformance/fuzz-reports/<gp-version>/traces/<case>/
       → boka/JAMTests/fuzz/<gp-version>/<case>/
   ```

3. Record the source commit and tiny/full configuration with the import. For local runs, record the generator version and settings.
4. Select the new version in `FuzzTests.swift` for both interpreter and JIT tests.

If no matching fuzz reports exist:
- Use the new vectors and their bundled block-import traces.
- Keep old fuzz files under their original version. Disable incompatible tests with `.disabled("reason")`, not an empty test body. Keep files needed by argument loaders even when tests are disabled.
- Add new-version tests when matching cases become available. Until then, that fuzz coverage is missing.

## Other sources

- **Javajam** (`javajamio/javajam-trace`) and **Jamduna** (`jam-duna/jamtestnet`): fetch each submodule separately and select a commit matching our GP version and configuration. Disable incompatible suites with a reason.
- **Crypto fixtures:** update independently from their source; they do not depend on a new GP fuzz corpus.
- **[paritytech/jam-m2-conformance](https://github.com/paritytech/jam-m2-conformance):** M2 test integration TBD.
