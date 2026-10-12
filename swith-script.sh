#!/bin/bash

set -e

NAMESPACE=app
SERVICE=app-svc
VERSION=$1

if [[ "$VERSION" != "green" && "$VERSION" != "blue" ]]; then
  echo "Usage: ./switch-script.sh [blue|green]"
  exit 1
fi

echo "Switching service selector to version=$VERSION..."

kubectl patch svc "$SERVICE" -n "$NAMESPACE" \
  -p '{"spec":{"selector":{"app":"vishva","version":"'"$VERSION"'"}}}'

echo "Switched to $VERSION"
