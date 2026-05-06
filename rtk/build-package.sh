#!/usr/bin/env bash
# Run this on the build server to produce rtk-linux-x86_64.tar.gz
# Requires: Rust >= 1.86, LD_LIBRARY_PATH set if cargo needs libssl.so.1.1
set -euo pipefail

REPO_DIR="/tmp/rtk-src"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="${OUT_DIR}/rtk-linux-x86_64.tar.gz"

# honour custom cargo/libssl paths from the build env
export PATH="/home/${USER}/.cargo/bin:${PATH}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/tools/common/pkgs/openssl11/lib}"

echo "Cloning rtk..."
rm -rf "${REPO_DIR}"
git clone --depth 1 https://github.com/rtk-ai/rtk.git "${REPO_DIR}"

echo "Building rtk (release)..."
cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml"

echo "Packaging..."
cp "${REPO_DIR}/target/release/rtk" "${OUT_DIR}/rtk"
tar -czf "${TARBALL}" -C "${OUT_DIR}" rtk install.sh
rm "${OUT_DIR}/rtk"

echo "Package ready: ${TARBALL}"
echo "Distribute and run:  tar xzf rtk-linux-x86_64.tar.gz && bash install.sh"
