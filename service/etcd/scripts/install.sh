#!/bin/sh
set -eu

[ $# = 1 ] || { >&2 echo "Usage: ${0} ETCD_VERSION"; exit 1; }

version="${1}"
if ! echo "${version}" | grep -qE '^v[0-9]'; then
  >&2 printf "ERROR: Must provide valid etcd version, got \`%s\`\n" "${version}"
  exit 1
fi

arch="$(arch | sed 's/x86_64/amd64/; s/aarch64/arm64/')"

rm -f "/opt/etcd-${version}-linux-${arch}.tar.gz"
rm -rf /opt/etcd && mkdir -p /opt/etcd

(
  set -x
  # Etcd binaries are now hosted on GitHub Releases
  # Example URL: https://github.com/etcd-io/etcd/releases/download/v3.5.13/etcd-v3.5.13-linux-amd64.tar.gz
  ETCD_DOWNLOAD_URL="https://github.com/etcd-io/etcd/releases/download/${version}/etcd-${version}-linux-${arch}.tar.gz"
  
  echo "Downloading etcd ${version} from ${ETCD_DOWNLOAD_URL}"
  curl --fail-with-body -L "${ETCD_DOWNLOAD_URL}" \
    -o "/opt/etcd-${version}-linux-${arch}.tar.gz"
  
  # It's good practice to verify checksums, but that's not implemented in this script.
  # Example:
  # curl -L "${ETCD_DOWNLOAD_URL}.sha256" -o "/opt/etcd-${version}-linux-${arch}.tar.gz.sha256"
  # sha256sum -c "/opt/etcd-${version}-linux-${arch}.tar.gz.sha256"
  # rm "/opt/etcd-${version}-linux-${arch}.tar.gz.sha256"

  tar xzvf "/opt/etcd-${version}-linux-${arch}.tar.gz" -C /opt/etcd --strip-components=1
  rm "/opt/etcd-${version}-linux-${arch}.tar.gz"
)
