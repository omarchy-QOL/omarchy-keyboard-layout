#!/bin/bash
set -euo pipefail

verification_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$(realpath "${1:?release checkout is required}")"
evidence_dir="$(realpath -m "${2:?evidence directory is required}")"
source_commit=2eb82d018e8e900a668f662bc2ca4f4358176bb5
expected_blob=95da11e5fe556587c6e230e067bd677fdf11f0e4
expected_sha256=9de81412986c72523e3fcc24cec74bff1eb59ab6478105f5b99b815406a9cd20

[[ $(git -C "$source_dir" rev-parse HEAD) == "$source_commit" ]]
[[ -z $(git -C "$source_dir" status --porcelain) ]]
[[ $(git -C "$source_dir" rev-parse HEAD:native/keyboard-layoutd) == "$expected_blob" ]]
mkdir -p "$evidence_dir/packages"

# verify public package bytes before installing the exact compiler and libraries
while IFS=$'\t' read -r package version digest; do
    filename="$package-$version-x86_64.pkg.tar.zst"
    url="https://archive.archlinux.org/packages/${package:0:1}/$package/$filename"
    curl --fail --location --retry 3 "$url" -o "$evidence_dir/packages/$filename"
    curl --fail --location --retry 3 "$url.sig" -o "$evidence_dir/packages/$filename.sig"
    printf '%s  %s\n' "$digest" "$filename" >> "$evidence_dir/packages/SHA256SUMS"
done < "$verification_dir/packages.tsv"
(cd "$evidence_dir/packages" && sha256sum --check SHA256SUMS)

cp /etc/pacman.conf "$evidence_dir/pacman.conf"
sed -i 's/^#*LocalFileSigLevel.*/LocalFileSigLevel = Required/' "$evidence_dir/pacman.conf"
pacman --config "$evidence_dir/pacman.conf" -U --noconfirm "$evidence_dir"/packages/*.pkg.tar.zst
while IFS=$'\t' read -r package version digest; do
    [[ $(pacman -Q "$package") == "$package $version" ]]
done < "$verification_dir/packages.tsv"

cp "$source_dir/native/keyboard-layoutd" "$evidence_dir/committed-keyboard-layoutd"
printf '%s  %s\n' "$expected_sha256" "$evidence_dir/committed-keyboard-layoutd" | sha256sum --check
git -C "$source_dir" archive HEAD native > "$evidence_dir/native-source.tar"
pacman -Q > "$evidence_dir/installed-packages.txt"
cc --version > "$evidence_dir/compiler.txt"
ld --version > "$evidence_dir/linker.txt"
pkg-config --cflags --libs json-c xkbcommon libutf8proc > "$evidence_dir/library-flags.txt"
cp "$verification_dir/packages.tsv" "$evidence_dir/packages.tsv"

# remove the shipped executable and all object files before compiling
make -C "$source_dir/native" clean
env -u CC -u CFLAGS -u CPPFLAGS -u LDFLAGS -u LDLIBS \
    -u LD_PRELOAD -u LIBRARY_PATH -u CPATH \
    make -C "$source_dir/native" all 2>&1 | tee "$evidence_dir/build.log"
cmp "$evidence_dir/committed-keyboard-layoutd" "$source_dir/native/keyboard-layoutd"
cp "$source_dir/native/keyboard-layoutd" "$evidence_dir/keyboard-layoutd"
"$evidence_dir/keyboard-layoutd" --probe | tee "$evidence_dir/probe.json"
sha256sum "$evidence_dir/keyboard-layoutd" "$evidence_dir/native-source.tar" \
    > "$evidence_dir/rebuilt-checksums.txt"
readelf -n "$evidence_dir/keyboard-layoutd" > "$evidence_dir/elf-notes.txt"
ldd "$evidence_dir/keyboard-layoutd" > "$evidence_dir/linked-libraries.txt"

jq -n \
    --arg source "$source_commit" \
    --arg blob "$expected_blob" \
    --arg digest "$expected_sha256" \
    --arg workflow "$GITHUB_SHA" \
    --arg ref "$GITHUB_REF" \
    --arg run "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
    --arg image "$BUILD_IMAGE" \
    --rawfile packages "$evidence_dir/installed-packages.txt" \
    --rawfile lock "$verification_dir/packages.tsv" \
    --rawfile build "$evidence_dir/build.log" \
    --rawfile compiler "$evidence_dir/compiler.txt" \
    --rawfile linker "$evidence_dir/linker.txt" \
    '{schemaVersion:1, sourceRepository:"https://github.com/omarchy-QOL/omarchy-keyboard-layout",
      sourceCommit:$source, committedGitBlob:$blob, rebuiltSha256:$digest,
      byteIdentical:true, builderWorkflowCommit:$workflow, builderRef:$ref,
      runUrl:$run, containerImage:$image, archiveSnapshot:"2026/11/03",
      packageLock:$lock, installedPackages:$packages, compiler:$compiler,
      linker:$linker, buildLog:$build}' > "$evidence_dir/rebuild-predicate.json"
printf 'Byte-identical rebuild of %s: %s\n' "$source_commit" "$expected_sha256"
