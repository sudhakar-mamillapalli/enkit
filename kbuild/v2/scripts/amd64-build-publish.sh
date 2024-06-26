#!/bin/sh

# Build and publish amd64 kernel artifacts for a particular configuration

set -e

SCRIPT_PATH="$(dirname $(realpath $0))"

ARCH=$1
FLAVOUR=$2
KERNEL_SRC="$3"
KERNEL_VERSION="$4"
BUILD_ROOT="$5"
ASTORE_LABEL="$6"
ASTORE_BASE="$7"
ASTORE_META_DIR="$8"

TARGET="${ARCH}-${FLAVOUR}"
BUILD_DEB_DIR="$BUILD_ROOT/deb-build/${TARGET}"
OUTPUT_DEB_DIR="$BUILD_ROOT/deb-out/${TARGET}"
OUTPUT_REPO_DIR="$BUILD_ROOT/apt-repo/${TARGET}"
OUTPUT_BAZEL_ARCHIVE_DIR="$BUILD_ROOT/bazel-archive/${TARGET}"
OUTPUT_APT_ARCHIVE_DIR="$BUILD_ROOT/deb-archive/${TARGET}"

# Builds the .deb kernel packages for arch, flavour
${SCRIPT_PATH}/build-debs.sh "$KERNEL_SRC" "$KERNEL_VERSION" "$ARCH" "$FLAVOUR" "$BUILD_DEB_DIR" "$OUTPUT_DEB_DIR"

# Creates a portable Debian APT repository for arch, flavour
${SCRIPT_PATH}/repo-deb.sh "$OUTPUT_DEB_DIR" "$ARCH" "$FLAVOUR" "$OUTPUT_REPO_DIR"

# Creates a bazel ready tarball for building kernel modules
${SCRIPT_PATH}/archive-bazel-deb.sh "$OUTPUT_DEB_DIR" "$ARCH" "$FLAVOUR" "$OUTPUT_BAZEL_ARCHIVE_DIR"

# Creates a tarball of a Debian APT repository for arch, flavour
${SCRIPT_PATH}/archive-deb.sh "$OUTPUT_DEB_DIR" "$OUTPUT_REPO_DIR" "$ARCH" "$FLAVOUR" "$OUTPUT_APT_ARCHIVE_DIR"

# Uploads the bazel ready tarball for arch, flavour
${SCRIPT_PATH}/upload-deb.sh      \
     "$OUTPUT_DEB_DIR"            \
     "$OUTPUT_BAZEL_ARCHIVE_DIR"  \
     "$OUTPUT_APT_ARCHIVE_DIR"    \
     "$ARCH"                      \
     "$FLAVOUR"                   \
     "$ASTORE_BASE"               \
     "$ASTORE_META_DIR"

# Generate Bazel include file fragment from upload meta-data files
${SCRIPT_PATH}/gen-bazel-meta.sh \
     "$OUTPUT_DEB_DIR"           \
     "$ARCH"                     \
     "$FLAVOUR"                  \
     "$ASTORE_BASE"              \
     "$ASTORE_META_DIR"          \
     "$ASTORE_LABEL"
