#!/bin/bash
set -e # Exit with nonzero exit code if anything fails
SOURCE_BRANCH="master"
TARGET_BRANCH="gh-pages-staging"
SERVICE_ACCOUNT="./service_account.json"
GITHUB_SSH_KEY="./deploy_key"
AUTH_CREDS="gs://gcpedu-github-secrets/goog-cred.json"

function doCompile {
  go get . || true
  go run compile.go
}

echo "Starting deployment"

echo "Copying auth credentials"
mkdir -p ~/.config/claat
~/google-cloud-sdk/bin/gsutil cp $AUTH_CREDS ~/.config/claat/goog-cred.json

# Pull requests and commits to other branches shouldn't try to deploy, just
# build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
  echo "Skipping deploy; just doing a build."
  doCompile
  exit 0
fi

# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`


# Clone the existing gh-pages for this repo into out/
git clone $REPO gh-pages
cd gh-pages

# open gh-pages-staging, or create a new branch with no history
git checkout $TARGET_BRANCH
cd ..

#clean out existing contents
rm -rf gh-pages/**/* || exit 0

# run our compile script
doCompile
cp -R build/* gh-pages/

echo "Updating stored auth creds if we've updated them."
~/google-cloud-sdk/bin/gsutil cp ~/.config/claat/goog-cred.json $AUTH_CREDS

# Now let's go have some fun with the cloned repo
cd gh-pages
git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

# If there are no changes to the compiled out (e.g. this is a README update)
# then just bail.
if [ -z `git diff --exit-code` ]; then
  echo "No changes to the output on this push; exiting."
  exit 0
fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
git add .
git commit -m "Deploy to GitHub Pages: ${SHA}"

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH

