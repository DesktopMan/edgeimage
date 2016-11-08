#!/bin/bash

# Internal script config
DEV=/dev/loop0
BOOT=${DEV}p1
ROOT=${DEV}p2
BOOT_MNT_DIR=/tmp/edgeboot
ROOT_MNT_DIR=/tmp/edgeroot
TMP_DIR=/tmp/edgetmp
W_DIR=w
FIRMWARE_FILE="$1"
OUTPUT_FILE="$2"
OUTPUT_SIZE="$3"

# Check parameters
if [ "$FIRMWARE_FILE" = "" ] || [ "$OUTPUT_FILE" = "" ] || [ "$OUTPUT_SIZE" = "" ]; then
	echo "Usage: ./edgeimage.sh <input firmware> <output image> <image size (MB)>"
	exit 0
fi

if [ ! -f "$FIRMWARE_FILE" ]; then
	echo "Invalid firmware file: $FIRMWARE_FILE"
	exit 1
fi

# Release tarball file names
KERNEL_ORIG=vmlinux.tmp
KERNEL_ORIG_MD5=vmlinux.tmp.md5
SQUASHFS_ORIG=squashfs.tmp
SQUASHFS_MD5_ORIG=squashfs.tmp.md5
VERSION_ORIG=version.tmp

# Target file names
KERNEL=vmlinux.64
KERNEL_MD5=vmlinux.64.md5
SQUASHFS=squashfs.img
SQUASHFS_MD5=squashfs.img.md5
VERSION=version

function check {
	if [ $? -ne 0 ]; then
		echo "Error: $1"
		cleanup
		exit 1
	fi
}

function cleanup {
	if [ "$1" = "all" ]; then
		rm -f $OUTPUT_FILE
		rm -f $OUTPUT_FILE.gz
	fi

	umount $BOOT_MNT_DIR 2>/dev/null
	umount $ROOT_MNT_DIR 2>/dev/null

	rm -rf $BOOT_MNT_DIR
	rm -rf $ROOT_MNT_DIR
	rm -rf $TMP_DIR

	losetup -d $DEV 2>/dev/null
}

# Cleanup
cleanup all

# Prepare directories
echo "Creating directories..."

mkdir $BOOT_MNT_DIR
check "Failed creating $BOOT_DIR"

mkdir $ROOT_MNT_DIR
check "Failed creating $ROOT_DIR"

mkdir $TMP_DIR
check "Failed creating $TMP_DIR"

# Prepare image
echo "Creating output image..."
dd if=/dev/zero of=$OUTPUT_FILE bs=1M count=$OUTPUT_SIZE 2>/dev/null
check "Failed creating output image"

# Setup loop device
echo "Setting up loop device..."
losetup $DEV $OUTPUT_FILE
check "Failed creating loop device"

## Repartition

# Remove everything
echo "Re-creating partition table..."
parted --script $DEV mktable msdos
check "Failed creating partition table"

# Boot
echo "Creating boot partition..."
parted --script $DEV mkpart primary fat32 1 150MB
check "Failed creating boot partition"

echo "Formatting boot partition..."
mkfs.vfat $BOOT 2>&1 > /dev/null
check "Failed formatting boot partition"

# Root
echo "Creating root partition..."
parted --script $DEV mkpart primary ext3 150MB 1900MB
check "Failed creating root partition"

echo "Formatting root partition..."
mkfs.ext3 -q $ROOT 2>/dev/null
check "Failed formatting root partition"

## Mount partitions
echo "Mounting boot parition..."
mount -t vfat $BOOT $BOOT_MNT_DIR
check "Failed mounting boot partition"

echo "Mounting root partition..."
mount -t ext3 $ROOT $ROOT_MNT_DIR
check "Failed mounting root partition"

## Reinstall

# Unpack image
echo "Unpacking EdgeOS release image..."
tar xf $FIRMWARE_FILE -C $TMP_DIR

# The kernel
echo "Verifying EdgeOS kernel..."
if [ `md5sum $TMP_DIR/$KERNEL_ORIG | awk -F ' ' '{print $1}'` != `cat $TMP_DIR/$KERNEL_ORIG_MD5` ]; then
	echo "Kernel from your image is corrupted! Check your image and start over."
	cleanup
	exit 1
fi

echo "Copying EdgeOS kernel to boot partition..."
cp $TMP_DIR/$KERNEL_ORIG $BOOT_MNT_DIR/$KERNEL
cp $TMP_DIR/$KERNEL_ORIG_MD5 $BOOT_MNT_DIR/$KERNEL_MD5

# The image
echo "Verifying EdgeOS system image..."
if [ `md5sum $TMP_DIR/$SQUASHFS_ORIG | awk -F ' ' '{print $1}'` != `cat $TMP_DIR/$SQUASHFS_MD5_ORIG` ]; then
	echo "System image from your image is corrupted! Check your image and start over."
	cleanup
	exit 1
fi

echo "Copying EdgeOS system image to root partition..."
mv $TMP_DIR/$SQUASHFS_ORIG $ROOT_MNT_DIR/$SQUASHFS
mv $TMP_DIR/$SQUASHFS_MD5_ORIG $ROOT_MNT_DIR/$SQUASHFS_MD5

echo "Copying version file to the root partition..."
mv $TMP_DIR/$VERSION_ORIG $ROOT_MNT_DIR/$VERSION

# Writable data dir
echo "Creating EdgeOS writable data directory..."
mkdir $ROOT_MNT_DIR/$W_DIR

# Compress image
echo "Compressing image..."
gzip -c $OUTPUT_FILE > $OUTPUT_FILE.gz
check "Failed compressing image"

## Cleanup
echo "Cleaning up..."
cleanup

echo "Image creation complete."
