#!/bin/bash

set -o errexit -o pipefail -o nounset

NEW_RELEASE=${GITHUB_REF##*/v}

export HOME=/home/builder

echo "::group::Setup"

echo "Getting AUR SSH Public keys"
ssh-keyscan aur.archlinux.org >> $HOME/.ssh/known_hosts

echo "Writing SSH Private keys to file"
echo -e "${INPUT_SSH_PRIVATE_KEY//_/\\n}" > $HOME/.ssh/aur

chmod 600 $HOME/.ssh/aur*

echo "Setting up Git"
git config --global user.name "$INPUT_GIT_USERNAME"
git config --global user.email "$INPUT_GIT_EMAIL"

REPO_URL="ssh://aur@aur.archlinux.org/${INPUT_PACKAGE_NAME}.git"

# Make the working directory
mkdir -p $HOME/package

# Copy the PKGBUILD file into the working directory
cp "$GITHUB_WORKSPACE/$INPUT_PKGBUILD_PATH" $HOME/package/PKGBUILD

cd $HOME/package

echo "::endgroup::Setup"

echo "::group::Build"

echo "Update the PKGBUILD with the new version"
sed -i "s/pkgver=.*/pkgver=$NEW_RELEASE/" PKGBUILD
sed -i "s/pkgrel=.*/pkgrel=1/" PKGBUILD

echo "Update the PKGBUILD with the new checksums"
updpkgsums

echo "Clone the AUR repo"
git clone "$REPO_URL"

echo "Building and installing dependencies"
makepkg --noconfirm -s -c

echo "Make the .SRCINFO file"
makepkg --printsrcinfo > .SRCINFO

echo "Copy the new PKGBUILD and .SRCINFO files into the AUR repo"
cp PKGBUILD .SRCINFO "$INPUT_PACKAGE_NAME/"

echo "::endgroup::Build"

echo "::group::Commit"

cd "$INPUT_PACKAGE_NAME"

echo "Push the new PKGBUILD and .SRCINFO files to the AUR repo"
git add PKGBUILD .SRCINFO
git commit -m "Update to $NEW_RELEASE"
git push

# Add github token to the git credential helper
git config --global core.askPass /cred-helper.sh
git config --global credential.helper cache

if [[ -z "${INPUT_SUBMODULE_PATH}" ]]; then
  echo "No submodule path provided, skipping submodule update"
else
  echo "Updating submodule"
  cd "$GITHUB_WORKSPACE"
  git submodule update --remote "$INPUT_SUBMODULE_PATH"
  git add "$INPUT_SUBMODULE_PATH"
  git commit -m "Update submodule to $NEW_RELEASE"
  git push
fi

echo "Update the PKGBUILD file in the main repo"
cd "$GITHUB_WORKSPACE"
cp $HOME/package/PKGBUILD "$INPUT_PKGBUILD_PATH"
git add "$INPUT_PKGBUILD_PATH"
git commit -m "Update PKGBUILD to $NEW_RELEASE"
git push

echo "::endgroup::Commit"