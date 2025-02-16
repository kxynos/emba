#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2023 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
#
# Author(s): Michael Messner

# Description:  Walk through a root directory and fix ELF permissions. Additionally
#               this script also tries to fix sym links which are regularly broken

BUSYBOX="/busybox"

ROOT_DIR="${1:-}"
if ! [[ -d "${ROOT_DIR}" ]]; then
  echo "[-] No valid root directory provided - Fix links and bin permissions failed"
  exit
fi

cp "$(command -v busybox)" "${ROOT_DIR}"
chmod +x "${ROOT_DIR}"/busybox

echo "[*] Identifying possible executable files"
mapfile -t POSSIBLE_ELFS < <(find "${ROOT_DIR}" -type f -exec file {} \; | grep "ELF\|executable" | cut -d: -f1)
mapfile -t POSSIBLE_SH < <(find "${ROOT_DIR}" -type f -name "*.sh")
POSSIBLE_EXES_ARR=( "${POSSIBLE_ELFS[@]}" "${POSSIBLE_SH[@]}" )

for POSSIBLE_EXE in "${POSSIBLE_EXES_ARR[@]}"; do
  [[ -x "${POSSIBLE_EXE}" ]] && continue
  echo "[*] Processing executable $(basename "${POSSIBLE_EXE}") - chmod privileges"
  chmod +x "${POSSIBLE_EXE}"
done

HOME_DIR="$(pwd)"
if [[ -d "${ROOT_DIR}" ]]; then
  cd "${ROOT_DIR}" || exit 1
else
  exit 1
fi

echo ""
echo "[*] Identifying possible dead symlinks"
mapfile -t POSSIBLE_DEAD_SYMLNKS < <(find "." -xdev -type f) # -exec file {} \; | grep "data\|ASCII\ text" | cut -d: -f1)

for POSSIBLE_DEAD_SYMLNK in "${POSSIBLE_DEAD_SYMLNKS[@]}"; do
  if [[ "${POSSIBLE_DEAD_SYMLNK}" == *"/proc/"* ]]; then
    continue
  fi
  DIR_ORIG_FILE=""
  if [[ "$(strings "${POSSIBLE_DEAD_SYMLNK}" | wc -l)" -gt 1 ]]; then
    continue
  fi
  if [[ "$(wc -c "${POSSIBLE_DEAD_SYMLNK}" | awk '{print $1}')" -gt 200 ]]; then
    continue
  fi
  if ! [[ "$(strings "${POSSIBLE_DEAD_SYMLNK}")" =~ ^[a-zA-Z0-9./_~'-']+$ ]]; then
    continue
  fi

  DIR_ORIG_FILE=$(dirname "${POSSIBLE_DEAD_SYMLNK}")
  [[ -z "${DIR_ORIG_FILE}" ]] && continue
  if ! [[ -d "${DIR_ORIG_FILE}" ]] && ! [[ -L "${DIR_ORIG_FILE}" ]]; then
    echo "[*] Directory to unknown detected: ${POSSIBLE_DEAD_SYMLNK} -> ${DIR_ORIG_FILE}"
  fi

  TMP_LNK_ORIG=$(strings "${POSSIBLE_DEAD_SYMLNK}")
  [[ -z "${TMP_LNK_ORIG}" ]] && TMP_LNK_ORIG=$(cat "${POSSIBLE_DEAD_SYMLNK}")
  [[ -z "${TMP_LNK_ORIG}" ]] && continue

  if [[  ${TMP_LNK_ORIG:0:1} == "/" ]]; then
    # if we have an absolute path we can just use it
    LNK_TARGET=".""${TMP_LNK_ORIG}"
    # sometimes the directory of the final dest does not exist - lets check and create it
    DIR_LNK_TARGET=$(dirname "${LNK_TARGET}")
    if ! [[ -d "${DIR_LNK_TARGET}" ]]; then
      echo "[*] Creating ${DIR_LNK_TARGET}"
      chroot . "${BUSYBOX}" mkdir -p "${DIR_LNK_TARGET}"
    fi
  else
    LNK_TARGET="${DIR_ORIG_FILE}"/"${TMP_LNK_ORIG}"
  fi

  if ! [[ -f "${LNK_TARGET}" ]] && ! [[ -d "${LNK_TARGET}" ]] && ! [[ -L "${LNK_TARGET}" ]]; then
    # if we have not target we need some indicator that this is a real link target
    # we check for a / in the dead symlink.
    ! [[ "${TMP_LNK_ORIG}" == *"/"* ]] && continue
    echo "[*] Unknown or non existent target detected: ${POSSIBLE_DEAD_SYMLNK} -> ${LNK_TARGET}"
    LNK_TARGET_NAME="$(basename "${LNK_TARGET}")"
    mapfile -t POSSIBLE_MATCHES < <(find "." -name "${LNK_TARGET_NAME}" -exec file {} \; | grep ELF | cut -d: -f1)
    for MATCH in "${POSSIBLE_MATCHES[@]}"; do
      echo "[*] Found possible matching file ${MATCH}"
    done
  fi

  LNK_TARGET=${LNK_TARGET/\./}
  POSSIBLE_SYMLNK_NAME=${POSSIBLE_DEAD_SYMLNK/\./}

  echo -e "[*] Symlink file ${POSSIBLE_SYMLNK_NAME} - ${LNK_TARGET}"
  chroot . "${BUSYBOX}" rm "${POSSIBLE_DEAD_SYMLNK}"
  chroot . "${BUSYBOX}" ln -s "${LNK_TARGET}" "${POSSIBLE_SYMLNK_NAME}"
done

cd "${HOME_DIR}" || exit 1
rm "${ROOT_DIR}"/busybox
