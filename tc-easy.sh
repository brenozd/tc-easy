#!/usr/bin/env sh

. "$PWD/src/utils.sh"
. "$PWD/src/add.sh"
. "$PWD/src/list.sh"
. "$PWD/src/remove.sh"

# Global Variables
__g_force_cmd=0

_show_help_global() {
    printf "Usage: tc-easy [add | rm | ls] OPTIONS\n"
    printf "Options: --help\n"
}

_parse_args_global() {
    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_global
                exit 0
                ;;
            -d|--debug)
                shift
                set -x
                ;;
            add)
                shift
                _parse_args_add "$@"
                exit 0
                ;;
            rm)
                shift
                _parse_args_rm "$@"
                exit 0
                ;;         # Handle
            ls)
                shift
                _parse_args_ls "$@"
                exit 0
                ;;
            -?*|*)
                _log "warn" "Unknown subcommand: $1, avaible subcommands are: add, rm and ls"
                _show_help_global
                exit 1
                ;;
        esac

    done
}

#check if user is root (maybe net admin is enough)
if [ "$(id -u)" -ne 0 ]; then
    _log "error" "tc-easy need to be run as super user"
    exit 1
fi

#check for dependencies (iproute2, awk etc)
if ! command -v ip >/dev/null; then
    _log "error" "iproute2 utility not found, consider installing it"
    exit 2
fi

if ! command -v awk >/dev/null; then
    _log "error" "awk utility not found, consider installing it"
    exit 2
fi

if ! command -v tc >/dev/null; then
    _log "warn" "TC utility not found, consider installing it"
    exit 2
fi

#check if ifb and tc are enabled
if ! _check_kmod_enabled "ifb"; then
    _log "warn" "IFB kernel module is deactivated, try to activate it? [y|n]"
    read -r __continue
    if [ "$__continue" = "y" ]; then
        if ! modprobe ifb; then
            _log "error" "Failed to activate module IFB"
            exit 3
        fi
    else
        exit 4
    fi

fi

if ! _check_kmod_enabled "htb"; then
    _log "warn" "HTB kernel module is deactivated, try to activate it? [y|n]"
    read -r __continue
    if [ "$__continue" = "y" ]; then
        if ! modprobe sch_htb; then
            _log "error" "Failed to activate module NetEm"
            exit 3
        fi
    else
        exit 4
    fi
fi

if ! _check_kmod_enabled "netem"; then
    _log "warn" "NetEm kernel module is deactivated, try to activate it? [y|n]"
    read -r __continue
    if [ "$__continue" = "y" ]; then
        if ! modprobe sch_netem; then
            _log "error" "Failed to activate module NetEm"
            exit 3
        fi
    else
        exit 4
    fi
fi

_parse_args_global "$@"
