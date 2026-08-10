#!/usr/bin/env bash
set -eu
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --signal=*|--kill-after=*) shift ;;
    --signal|--kill-after) shift 2 ;;
    *s) shift; break ;;
    *) break ;;
  esac
done
exec "$@"
