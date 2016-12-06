#!/bin/bash
set -e # Exit with nonzero exit code
SOURCE_BRANCH="builder"
TARGET_BRANCH="staging"
SERVICE_ACCOUNT="./service_account.json"
GITHUB_SSH_KEY="./deploy_key"
AUTH_CREDS="gs://gcpedu-github-secrets/goog-cred.json"

function doCompile {
  echo "Getting claat tool"
  go get github.com/googlecodelabs/tools/claat || true

  echo "Getting compile.go's deps"
  go get . || true
  go run compile.go
}

function doSetup {
  local key="encrypted_${ENCRYPTION_LABEL}_key"
  local iv="encrypted_${ENCRYPTION_LABEL}_iv"
  key=${!key}
  iv=${!iv}

  # Decrypt id_rsa and service_account.json
  openssl aes-256-cbc \
    -K $key \
    -iv $iv \
    -in secrets.tar.enc -out secrets.tar -d
  tar xvf secrets.tar

  # Install gcloud util
  curl https://sdk.cloud.google.com | bash
  ~/google-cloud-sdk/bin/gcloud auth activate-service-account --key-file=service_account.json

  # Add ssh keys to git client
  eval `ssh-agent -s`
  ssh-add id_rsa

}

echo "Validating configuration json"
for f in *.json; do
  cat $f | python -m json.tool > /dev/null
done

# See if this is a pull request
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
  echo "Skipping deploy as this is just a pull req"
  exit 0
fi

echo "Doing setup"
doSetup

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
git clone $REPO out
cd out
git checkout $TARGET_BRANCH
cd ..

# Clean out existing content
rm -rf out/**/* || exit 0

# run our compile script
doCompile

# Copy build
cp -R build/* out/
echo "${SHA}" > out/VERSION
echo '<!-- VERSION: '${SHA}' -->' >> out/index.html

echo "Updating stored auth creds if we've updated them."
~/google-cloud-sdk/bin/gsutil cp ~/.config/claat/goog-cred.json $AUTH_CREDS

# Now let's go have some fun with the cloned repo
cd out
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
git add --all .
git commit -m "Deploy to GitHub Pages: ${SHA}"

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH

