#!/usr/bin/env bash
(return 0 2>/dev/null)
_toolchain_sourced=$?

if [ "$_toolchain_sourced" -ne 0 ]; then
    echo "WARNING: this script was executed, not sourced. PATH changes would" >&2
    echo "be lost immediately. Re-run it as:" >&2
    echo "    source scripts/setup_toolchain.sh" >&2
fi

_toolchain_bail() {
    echo "ERROR: $1" >&2
    if [ "$_toolchain_sourced" -eq 0 ]; then
        return 1
    fi
    exit 1
}

_toolchain_candidates=()
if [ -n "${OSS_CAD_SUITE:-}" ]; then
    if [ -f "$OSS_CAD_SUITE/environment" ]; then
        _toolchain_found="$OSS_CAD_SUITE"
    else
        _toolchain_bail "OSS_CAD_SUITE=$OSS_CAD_SUITE was set, but $OSS_CAD_SUITE/environment does not exist."
        unset _toolchain_sourced _toolchain_candidates _toolchain_found _toolchain_dir
        return 1 2>/dev/null || exit 1
    fi
else
    _toolchain_candidates+=(
        "$HOME/tools/oss-cad-suite"
        "$HOME/oss-cad-suite"
        "/opt/oss-cad-suite"
        "/usr/local/oss-cad-suite"
    )

    _toolchain_found=""
    for _toolchain_dir in "${_toolchain_candidates[@]}"; do
        if [ -f "$_toolchain_dir/environment" ]; then
            _toolchain_found="$_toolchain_dir"
            break
        fi
    done

    if [ -z "$_toolchain_found" ]; then
        _toolchain_bail "could not find an OSS CAD Suite install. Checked: ${_toolchain_candidates[*]}. Install it from https://github.com/YosysHQ/oss-cad-suite-build, then either place it at ~/tools/oss-cad-suite or point this script at it with OSS_CAD_SUITE=/path/to/oss-cad-suite."
        unset _toolchain_sourced _toolchain_candidates _toolchain_found _toolchain_dir
        return 1 2>/dev/null || exit 1
    fi
fi

echo "Using OSS CAD Suite at: $_toolchain_found"
# shellcheck disable=SC1091
source "$_toolchain_found/environment"

_toolchain_missing=()
for _toolchain_tool in yosys nextpnr-ecp5; do
    command -v "$_toolchain_tool" >/dev/null 2>&1 || _toolchain_missing+=("$_toolchain_tool")
done

if [ "${#_toolchain_missing[@]}" -ne 0 ]; then
    _toolchain_bail "sourced $_toolchain_found/environment but still missing: ${_toolchain_missing[*]}. This doesn't look like a complete OSS CAD Suite install."
    unset _toolchain_sourced _toolchain_candidates _toolchain_found _toolchain_missing _toolchain_dir _toolchain_tool
    return 1 2>/dev/null || exit 1
fi

echo "--- toolchain versions ---"
if [ -f "$_toolchain_found/VERSION" ]; then
    echo "OSS CAD Suite build: $(cat "$_toolchain_found/VERSION")"
fi
yosys -V
nextpnr-ecp5 --version 2>&1 | head -1
echo "--------------------------"
echo "yosys and nextpnr-ecp5 are now on PATH. Run scripts/run_synthesis.sh to" \
     "synthesize and place-and-route all four designs."

unset _toolchain_sourced _toolchain_candidates _toolchain_found _toolchain_missing \
      _toolchain_dir _toolchain_tool
unset -f _toolchain_bail
