#!/bin/sh

# Build Enfabrica kernel tree release directories.

set -e

# Ensure this script is run from the root of the kernel tree
if [ ! -f MAINTAINERS ] ; then
    echo "Error: This script must be run from the root of the kernel tree"
    exit 1
fi

# Default version suffix
DEFAULT_VERSION_SUFFIX=""

# Default kernel architecture
DEFAULT_ARCH="amd64"

# Default kernel flavour
DEFAULT_FLAVOUR="generic"

# The following ENF_ variables provide an external API and can be set
# before running this script:

# Version suffix
RT_VERSION_SUFFIX="${ENF_VERSION_SUFFIX:-${DEFAULT_VERSION_SUFFIX}}"

# Kernel arch
RT_ARCH="${ENF_ARCH:-${DEFAULT_ARCH}}"

# Kernel flavour
RT_FLAVOUR="${ENF_FLAVOUR:-${DEFAULT_FLAVOUR}}"

usage() {
    cat <<EOF
USAGE:
    ${0##*/} [OPTIONS]

OPTIONS:
    -v version suffix
        A suffix to append to the version information
        from the debian/changelog file.

        The default is "$DEFAULT_VERSION_SUFFIX".

    -a kernel architecture

        The CPU architecture to compile for.  One of "amd64" or "arm64".

        The default is "$DEFAULT_ARCH".

    -f kernel flavour

        A particular kernel configuration for an architecture.
        See debian.master/rules.d/<arch>.mk in the kernel
        repo for a list of available flavours for an arch.

        The default is "$DEFAULT_FLAVOUR".

ENVIRONMENT VARIABLES

Some options can also be set via environment variables:

ENF_VERSION_SUFFIX:  (current_value: ${ENF_VERSION_SUFFIX:-unset})
ENF_ARCH:            (current_value: ${ENF_ARCH:-unset})
ENF_FLAVOUR:         (current_value: ${ENF_FLAVOUR:-unset})

In all cases, the command line arguments take precedence.

EOF
}

# Command line argument override any environment variables
while getopts hcv:a:f:b: opt ; do
    case $opt in
        v)
            RT_VERSION_SUFFIX=$OPTARG
            ;;
        a)
            RT_ARCH=$OPTARG
            ;;
        f)
            RT_FLAVOUR=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift `expr $OPTIND - 1`

case "$RT_ARCH" in
    amd64 | arm64) ;;
    *)
        echo "Error: Unsupported architecture: $RT_ARCH."
        echo "Supported architectures are 'amd64' and 'arm64'."
        exit 1
esac

for var in RT_VERSION_SUFFIX RT_ARCH RT_FLAVOUR ; do
    printf "%-20s:   %s\n" "$var" "$(eval echo -n \$$var)"
done

# Create a kernel version string
function gen_kernel_version() {
    local suffix="$1"
    local flavour="$2"

    # Create a kernel suffix that mimics what debian does
    DEBIAN="debian.master"
    pkg_name="linux"
    linux_version=$(sed -n '1s/^linux.*(\(.*\)-.*).*$/\1/p' ${DEBIAN}/changelog)
    if [ -z "LINUX_VERSION" ] ; then
        echo "ERROR: unable to determine Debian kernel version"
        exit 1
    fi

    # Next tease out the Debian changelog ABI number.  Need to match
    # any built .debs...
    revision=$(sed -n "s/^linux\ .*(${linux_version}-\(.*\)).*$/\1/p" ${DEBIAN}/changelog)
    debian_abi=$(echo $revision | sed -r -e 's/([^\+~]*)\.[^\.]+(~.*)?(\+.*)?$/\1/')

    kernel_version="${linux_version}-${debian_abi}${suffix}-${flavour}"
    echo -n "$kernel_version"
}

# Generate configs
fakeroot debian/rules clean
fakeroot debian/rules genconfigs arch="$RT_ARCH"

kconfig="CONFIGS/${RT_ARCH}-config.flavour.${RT_FLAVOUR}"
if [ ! -r "$kconfig" ] ; then
    echo "ERROR: Unable to find kernel config for arch-flavour: ${RT_ARCH}-${RT_FLAVOUR}"
    exit 1
fi

# The output build directory must be a sibling of the current source directory.
parent_dir="$(dirname $PWD)"
build_dir="${parent_dir}/install/build"
rm -rf $build_dir
mkdir -p $build_dir

kernel_version="$(gen_kernel_version $RT_VERSION_SUFFIX $RT_FLAVOUR)"
echo "$kernel_version" > "${build_dir}/enf-kernel-version.txt"

# setup kernel config file
cp "$kconfig" "${build_dir}/.config"

case "$RT_ARCH" in
    arm64)
        arch_args="ARCH=$RT_ARCH CROSS_COMPILE=aarch64-linux-gnu-"
        arch_image="Image"
        output_image="arch/arm64/boot/Image"
        ;;
    amd64)
        arch_args=""
        arch_image="bzImage"
        output_image="arch/x86/boot/bzImage"
        ;;
    *)
        echo "ERROR: Unknown arch: $RT_ARCH"
        exit 1
esac

NPROC=$(( $(nproc) / 4 ))

echo "Building kernel spec: ${RT_ARCH}-${RT_FLAVOUR}"
make -s \
     O="$build_dir" \
     -j $NPROC \
     $arch_args \
     KERNELRELEASE="$kernel_version" \
     prepare modules \
     $arch_image

# make source symlink relative
rm -f "${build_dir}/source"
ln -s --relative . "${build_dir}/source"

# use relative path in build_dir Makefile
cat <<EOF > "${build_dir}/Makefile"
# Automatically generated: don't edit
include ./source/Makefile
EOF

# remove a bunch of unneeded stuff from build directory
PATTERNS=".*.cmd *.a *.o *.d *.ko *.order *.mod *.mod.c *.mod.o *.log"
for p in $PATTERNS ; do
    find "$build_dir" -name $p -type f -exec rm -f {} +
done

# TODO: remove even more stuff from the "source" and "build" directory

# Create bazel installer script
install_script="${parent_dir}/install-${kernel_version}.sh"
cat <<EOF > "$install_script"
#!/bin/sh

echo "install"

EOF

chmod +x $install_script

# Move kernel image into boot directory
boot_dir="${parent_dir}/boot"
mkdir -p "$boot_dir"
cp "${build_dir}/$output_image" "${boot_dir}/vmlinuz-${kernel_version}"
