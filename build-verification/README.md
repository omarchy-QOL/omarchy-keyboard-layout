# Native 0.2.4 verification

This branch verifies the executable already shipped in release commit
`2eb82d018e8e900a668f662bc2ca4f4358176bb5`. It does not replace the release
binary or change the release tag.

The workflow uses a digest-pinned official Arch container and a fixed Arch
repository snapshot. It downloads the compiler and library packages in
`packages.tsv`, checks their SHA-256 digests, requires package signatures,
and installs those exact versions before building.

The shipped executable and all build objects are removed before compilation.
Attestations are generated only after `cmp` confirms identical rebuilt bytes.
The evidence records the exact release source, builder workflow commit,
container digest, package inputs, compiler, linker, commands and comparison.

GitHub's standard build-provenance attestation identifies the verification
workflow. A second signed predicate explicitly binds the rebuilt binary to
the release source commit and committed Git blob.

Verify a downloaded executable with:

```bash
gh attestation verify keyboard-layoutd -R omarchy-QOL/omarchy-keyboard-layout
gh attestation verify keyboard-layoutd -R omarchy-QOL/omarchy-keyboard-layout \
  --predicate-type https://github.com/omarchy-QOL/omarchy-keyboard-layout/attestations/native-rebuild/v1
```

Inspect the comparison predicate and confirm its `sourceCommit`,
`committedGitBlob`, `rebuiltSha256`, and `byteIdentical` fields. Also inspect
the
workflow at the attested builder commit and its public Actions log.
