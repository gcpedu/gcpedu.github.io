#!/bin/bash
set -e # Exit with nonzero exit code
go get -u github.com/golang/lint/golint

echo "Golang lint"
golint

echo "Lint json"
for f in *.json; do
  if [ "$f" != "service_account.json" ]; then
    echo "Linting $f"
    cat $f | python -m json.tool > /tmp/json
    diff $f /tmp/json
  fi
done

