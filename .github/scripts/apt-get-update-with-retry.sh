#!/usr/bin/env bash

set -euo pipefail

for attempt in 1 2 3; do
  echo "apt-get update attempt ${attempt}/3"
  sudo rm -rf /var/lib/apt/lists/*

  if sudo apt-get clean && sudo apt-get \
    -o Acquire::Retries=3 \
    -o Acquire::http::No-Cache=true \
    -o Acquire::https::No-Cache=true \
    update; then
    exit 0
  fi

  if [ "$attempt" -lt 3 ]; then
    echo "apt-get update failed; retrying after a short cooldown..."
    sleep $((attempt * 10))
  fi
done

echo "apt-get update failed after 3 attempts."
exit 1
