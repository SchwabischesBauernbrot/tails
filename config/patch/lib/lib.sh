# shellcheck shell=bash

PATCH_COMMIT_FILE=/var/lib/tails-patch-commit
PATCHES_DIR=config/chroot_local-patches
LIB_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
GIT_REPO=$(realpath "${LIB_DIR}/../../..")

run_with_plymouth_msg() {
  local msg="$1"
  shift
  plymouth --ping && plymouth display-message --text="${msg}"
  "$@"
  local ret=$?
  # `plymouth hide-message` doesn't work (#20401)	
  plymouth --ping && plymouth display-message --text=""
  return $ret
}

branch() {
  git -C "${GIT_REPO}" rev-parse --abbrev-ref HEAD
}

modified_files() {
  local commit="$1"
  local dir="$2"
  git -C "${GIT_REPO}" --no-pager diff "${commit}" --name-only --no-renames -- "${dir}"
}

untracked_files() {
  local dir="$1"
  git -C "${GIT_REPO}" --no-pager ls-files --others --exclude-standard -- "${dir}"
}

untracked_and_modified_files() {
  # This function is called in a subshell, so we need to set options again
  set -euo pipefail
  local commit="$1"
  local dir="$2"
  local modified
  modified="$(modified_files "${commit}" "${dir}")"
  local untracked
  untracked="$(untracked_files "${dir}")"
  local all
  all="${modified}"$'\n'"${untracked}"
  # The grep -v '^$' is to remove empty lines
  echo "${all}" | sort -u | grep -v '^$' || true
}

tails_commit() {
  # This function is called in a subshell, so we need to set options again
  set -euo pipefail
  grep TAILS_GIT_COMMIT /etc/os-release | cut -d= -f2 | tr -d '"'
}

patch_base_ref() {
  # Get the base reference which the working tree should be compared to
  if [ -e "${PATCH_COMMIT_FILE}" ]; then
    cat "${PATCH_COMMIT_FILE}"
  else
    tails_commit
  fi
}

update_patch_base_ref() {
  # Store the current HEAD as the new base commit so that subsequent
  # executions of the script know what to compare to.
  # Note: This is not perfect because we copy/bind mount files from the
  # working tree, including files with uncommitted changes. By storing
  # HEAD as the base commit, if any uncommitted changes are reverted
  # before the next execution, those changes will not be reverted by the
  # copy/bind script because they are not in the base commit.
  mkdir -p "$(dirname "${PATCH_COMMIT_FILE}")"
  git -C "${GIT_REPO}" rev-parse HEAD > "${PATCH_COMMIT_FILE}"
}

reapply_patches() {
  local commit="$1"
  local dest="$2"
  local patches patch
  patches=$(untracked_and_modified_files "${commit}" "${PATCHES_DIR}")
  for patch in ${patches}; do
    if ! [ -f "${GIT_REPO}/${patch}" ]; then
      echo >&2 "Patch ${patch} doesn't exist in the working tree, reverting the version" \
        "from the base commit."
      git -C "${GIT_REPO}" show "${commit}:${patch}" |
        patch -p1 --reverse --batch --directory "${dest}" || true
      continue
    fi

    if ! git -C "${GIT_REPO}" show "${commit}:${patch}" >/dev/null 2>&1; then
      echo >&2 "Patch ${patch} doesn't exist on the base commit, applying the" \
        "version from the working tree."
      patch -p1 --batch --directory "${dest}" <"${GIT_REPO}/${patch}" || true
      continue
    fi

    # The patch exists on both the base commit and the working tree, so
    # we first revert the version from the base commit and then apply
    # the version from the working tree.
    echo >&2 "Reapplying patch ${patch}"
    git -C "${GIT_REPO}" show "${commit}:${patch}" |
      patch -p1 --reverse --batch --directory "${dest}" || true
    patch -p1 --batch --directory "${dest}" <"${GIT_REPO}/${patch}" || true
  done
}

has_changes() {
  local commit="$1"
  local dir="$2"
  ! git -C "${GIT_REPO}" diff --quiet "${commit}" -- "${dir}"
}

apply_changes() {
  local commit="$1"
  local dir file src dest

  # Reload dconf db if any dconf files were changed
  dir="${GIT_REPO}/config/chroot_local-includes/etc/dconf"
  if has_changes "${commit}" "${dir}"; then
    dconf update
  fi

  # Call 52-update-rc.d if it was changed
  file="${GIT_REPO}/config/chroot_local-hooks/52-update-rc.d"
  if [ -f "${file}" ] && has_changes "${commit}" "${file}"; then
    run_with_plymouth_msg "Updating systemd units" "${file}"
  fi

  # Call 52-update-systemd-units if it was changed
  file="${GIT_REPO}/config/chroot_local-hooks/52-update-systemd-units"
  if [ -f "${file}" ] && has_changes "${commit}" "${file}"; then
    run_with_plymouth_msg "Updating systemd units" "${file}"
  fi

  # Install modified dpkg hook (only useful if
  # /etc/apt/apt.conf.d/80tails-additional-software.disabled was modified)
  src="/etc/apt/apt.conf.d/80tails-additional-software.disabled"
  dest="/etc/apt/apt.conf.d/80tails-additional-software"
  if [ -e "${src}" ]; then
    ln -sf "${src}" "${dest}" || true
  fi
}
