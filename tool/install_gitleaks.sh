#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo 'usage: install_gitleaks.sh <destination-directory>' >&2
  exit 64
fi

destination=$1
case "$(uname -s):$(uname -m)" in
  Linux:x86_64) archive=linux_x64; checksum=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
  Linux:aarch64|Linux:arm64) archive=linux_arm64; checksum=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;;
  Darwin:x86_64) archive=darwin_x64; checksum=dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709 ;;
  Darwin:arm64) archive=darwin_arm64; checksum=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5 ;;
  *) echo "unsupported platform: $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$destination"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM
url="https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_${archive}.tar.gz"
archive_path="$tmpdir/gitleaks.tar.gz"
curl --fail --location --silent --show-error "$url" --output "$archive_path"
case "$(uname -s)" in
  Linux) actual=$(sha256sum "$archive_path" | awk '{print $1}') ;;
  Darwin) actual=$(shasum -a 256 "$archive_path" | awk '{print $1}') ;;
  *) echo 'no supported SHA-256 utility for this platform' >&2; exit 1 ;;
esac
if [ "$actual" != "$checksum" ]; then
  echo 'gitleaks archive checksum mismatch' >&2
  exit 1
fi
tar -xzf "$archive_path" -C "$tmpdir" gitleaks
install -m 755 "$tmpdir/gitleaks" "$destination/gitleaks"
