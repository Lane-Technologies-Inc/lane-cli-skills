#!/usr/bin/env bash
if ! command -v lane-cli >/dev/null 2>&1; then
  echo "WARNING: lane-cli not found. Plugin features will not work." >&2
  echo "Install with: npm i @getonlane/lane-cli -g" >&2
else
  REMOTE_VERSION=$(curl -s https://registry.npmjs.org/@getonlane/lane-cli/latest | jq -r .version)
  LOCAL_VERSION=$(lane-cli -v)
  if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo "WARNING: lane-cli version ($LOCAL_VERSION) is out of date. Latest is $REMOTE_VERSION." >&2
    echo "Update with: npm i @getonlane/lane-cli -g" >&2
  fi
fi
exit 0