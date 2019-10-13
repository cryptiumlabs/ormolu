# Format Ormolu using current version of Ormolu.

set -xe

stack install

export LANG="C.UTF-8"

ormolu --mode inplace $(find src -type f \( -name "*.hs" -o -name "*.hs-boot" \))
ormolu --mode inplace $(find tests -type f -name "*.hs")
