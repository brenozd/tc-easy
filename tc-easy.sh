#!/usr/bin/env sh

# set -e
# set -x

_log() {
    echo "$@"
}

# Utilizar modprobe para habilitar os módulos utilizados
_check_kmod_enabled() {
    module_state=$(awk -v mod="$1" '$1 ~mod {print $5}' /proc/modules)
    if [ "$module_state" = "Live" ]; then
        # _log "Module $1 is enabled"
        return 0
    fi
    # _log "Module $1 is disabled"
    return 1
}

_check_if_interface_exists() {
    interfaces=$(ls /sys/class/net)
    for i in $interfaces; do
        if [ "$1" = "$i" ]; then
            # _log "Found interface $1"
            return 0
        fi
    done
    # _log "Interface $1 is not available"
    return 1
}

_get_dev_qdisc() {
    __dev="$1"
    __classid="$2"
    __qdisc=$(tc qdisc show dev "$__dev" "$__classid")
    if [ -z "$__qdisc" ]; then
        return 1
    fi
    echo "$__qdisc" | awk '{print $2}'
    return 0
}

_show_help_add() {
    echo "Usage: tc-easy add dev <interface> from <ip> to <ip> OPTIONS"
    printf "Options:\n\t--latency=<value>\n\t--packetloss=<value>\n\t--jitter=<value> (only used if --latency is passed)\n\t--download=<value>\n\t--upload=<value>\n"
}

_add_route_shaping() {
    __dev=""
    __src_ip=""
    __dst_ip=""
    __latency=""
    __jitter=""
    __packet_loss=""
    __reorder=""
    __duplication=""
    __corruption=""
    __bandwidth_download="1000"
    __bandwidth_upload="1000"

    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_add
                exit
                ;;
            dev)
                shift
                _check_if_interface_exists "$1" || return
                __dev="$1"
                shift
                ;;
            from)
                shift
                __src_ip="$1"
                shift
                ;;
            to)
                shift
                __dst_ip="$1"
                shift
                ;;
            --latency|-l)
                shift
                __latency="$1"
                shift
                ;;
            --jitter|-j)
                shift
                __jitter="$1"
                shift
                ;;
            --packetloss|-p)
                shift
                __packet_loss="$1"
                shift
                ;;         # Handle
            --reorder|-r)
                shift
                __reorder="$1"
                shift
                ;;
            --duplication)
                shift
                __duplication="$1"
                shift
                ;;
            --corruption|-c)
                shift
                __corruption="$1"
                shift
                ;;
            --download|-d)
                shift
                __bandwidth_upload="$1"
                shift
                ;;
            --upload|-u)
                shift
                __bandwidth_download="$1"
                shift
                ;;
            -?*)
                printf 'WARN: Unknown add option: %s\n' "$1" >&2
                _show_help_add
                ;;
            *)
                break
        esac
    done

    if [ -z "$__dev" ] || [ -z "$__src_ip" ] || [ -z "$__dst_ip" ]; then
        printf 'Missing arguments\n'
        _show_help_add
        return
    fi

    __dev_qdisc=$(_get_dev_qdisc "$__dev" "root")
    if [ "$__dev_qdisc" != "htb" ]; then
        echo "Interface $__dev has qdisc $__dev_qdisc associated with it" >&2
        echo "Do you want to continue? All qdisc from interface $__dev will be deleted [y|n]"
        read -r __continue
        if [ "$__continue" != "y" ]; then
            echo "Aborting tc-easy"
        fi
    fi

    __netem_params=""
    if [ -n "$__latency" ]; then
        __netem_params="$__netem_params delay ${__latency}ms"
        # TODO: Checar se setando o jitter > latencia o TC buga
        if [ -n "$__jitter" ]; then
            __netem_params="$__netem_params ${__jitter}ms distribution normal"
        fi
    fi

    if [ -n "$__packet_loss" ]; then
        __netem_params="$__netem_params loss ${__packet_loss}%"
    fi

    if [ -n "$__reorder" ]; then
        __netem_params="$__netem_params reorder ${__reorder}%"
    fi

    if [ -n "$__duplication" ]; then
        __netem_params="$__netem_params reorder ${__duplication}%"
    fi

    if [ -n "$__corruption" ]; then
        __netem_params="$__netem_params corrupt ${__corruption}%"
    fi

    __ifb_dev="ifb_$__dev"
    if _check_if_interface_exists "$__ifb_dev"; then
        ip link delete "$__ifb_dev"
    fi

    ip link add name "$__ifb_dev" type ifb
    ip link set dev "$__ifb_dev" up


    tc qdisc del dev "$__ifb_dev" root >/dev/null 2>&1
    tc qdisc del dev "$__dev" root >/dev/null 2>&1

    # TODO: Arrumar os handles do qdisc, começando em 0
    # TODO: Adicionar fifo_fast como classe default do htb
    # TODO: Se houver outro qdisc como root, perguntar para o usuario o que fazer
    # TODO: Limitar a banda do root como a

    __interface_speed=$(cat /sys/class/net/"$__dev"/speed)
    tc qdisc add dev "$__dev" root handle 1: htb default 1
    tc qdisc add dev "$__ifb_dev" root handle 1: htb default 1

    # TODO: checar se há banda disponível para a classe
    tc class add dev "$__dev" parent 1: classid 1:2 htb rate "$__bandwidth_upload"mbps ceil "$__bandwidth_upload"mbps prio 2
    tc class add dev "$__ifb_dev" parent 1: classid 1:1 htb rate "$__bandwidth_upload"mbps ceil "$__bandwidth_upload"mbps prio 2

    if [ -n "$__netem_params" ]; then
        # Remove trailing whitespaces, otherwhise TC does not accept __netem_params
        __netem_params=$(echo "$__netem_params" | cut -f 2- -d ' ')
        tc qdisc add dev "$__dev" parent 1:2 handle 10:0 netem $__netem_params
        tc qdisc add dev "$__ifb_dev" parent 1:1 handle 10:0 netem $__netem_params
    fi

    tc filter add dev "$__dev" protocol ip parent 1:0 prio 2 u32 match ip src "$__src_ip" match ip dst "$__dst_ip" flowid 1:2
    tc filter add dev "$__ifb_dev" protocol ip parent 1:0 prio 2 u32 match ip src "$__src_ip" match ip dst "$__dst_ip" flowid 1:2

    if _get_dev_qdisc "$__dev" "ingress"; then
        tc qdisc del dev "$__dev" ingress
    fi

    tc qdisc add dev "$__dev" ingress
    tc filter add dev "$__dev" ingress matchall action mirred egress redirect dev "$__ifb_dev"

    printf 'Added route from %s to %s via %s\n' "$__src_ip" "$__dst_ip" "$__dev"

}

_parse_args_rm() {
    __dev=""
    __src_ip=""
    __dst_ip=""

    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_add
                exit
                ;;
            dev)
                shift
                _check_if_interface_exists "$1" || return
                __dev="$1"
                shift
                ;;
            from)
                shift
                __src_ip="$1"
                shift
                ;;
            to)
                shift
                __dst_ip="$1"
                shift
                ;;
            -?*)
                printf 'WARN: Unknown add option: %s\n' "$1" >&2
                _show_help_add
                ;;
            *)
                break
        esac
    done

    tc qdisc del dev "$__dev" root >/dev/null 2>&1
    if _get_dev_qdisc "$__dev" "ingress"; then
        tc qdisc del dev "$__dev" ingress >/dev/null 2>&1
    fi

    __ifb_dev="ifb_$__dev"
    if _check_if_interface_exists "$__ifb_dev"; then
        ip link delete "$__ifb_dev"
    fi

    printf 'Removed route from %s to %s via %s\n' "$__src_ip" "$__dst_ip" "$__dev"

}

_parse_args_ls() {
    echo "Not implemented yet"
}

_show_help_global() {
    echo "Usage: tc-easy [add | rm | ls] OPTIONS"
    echo "Options: --help"
}

_parse_args_global() {
    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_global
                exit
                ;;
            add)
                shift
                _add_route_shaping "$@"
                ;;
            rm)
                shift
                _parse_args_rm "$@"
                ;;         # Handle
            ls)
                shift
                _parse_args_ls "$@"
                ;;
            -?*)
                printf 'WARN: Unknown subcommand: %s, avaible subcommands are: add, rm and ls\n' "$1" >&2
                _show_help_global
                ;;
            *)
                break
        esac
        exit
    done
}

#check if user is root (maybe net admin is enough)
if [ "$(id -u)" -ne 0 ]; then
    _log "tc-easy need to be run as super user"
    exit 1
fi

#check for dependencies (iproute2, awk etc)
if ! command -v ip >/dev/null; then
    _log "iproute2 utility not found, consider installing it"
    exit 2
fi

if ! command -v awk >/dev/null; then
    _log "awk utility not found, consider installing it"
    exit 2
fi

if ! command -v tc >/dev/null; then
    _log "TC utility not found, consider installing it"
    exit 2
fi

#check if ifb and tc are enabled
if ! _check_kmod_enabled "ifb"; then
    _log "IFB kernel module is deactivated, consider enabling it"
    exit 3
fi

if ! _check_kmod_enabled "netem"; then
    _log "NetEm kernel module is deactivated, consider enabling it"
    exit 4
fi

_parse_args_global "$@"