#!/usr/bin/env sh

# set -e
set -x

_log() {
    case $1 in
        error)
            __tag="ERROR"
            __redirect="2"
        ;;
        warn)
            __tag="WARN"
            __redirect="2"
        ;;
        info)
            __tag="INFO"
            __redirect="1"
        ;;
        debug)
            __tag="DEBUG"
            __redirect="1"
        ;;
    esac

    printf '%s - [%s] - %s\n' "$(date)" "$__tag" "$2"
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

_parse_args_add() {
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
        _show_help_add
        return
    fi

    # TODO: Antes de fazer qualquer coisa checar se há banda disponível no TC
    __ifb_dev="ifb_$__dev"
    if ! _check_if_interface_exists "$__ifb_dev"; then
        ip link add name "$__ifb_dev" type ifb
    fi
    ip link set dev "$__ifb_dev" up

    _add_route "$__dev"     "$__src_ip" "$__dst_ip" "$__latency" "$__jitter" "$__packet_loss" "$__reorder" "$__duplication" "$__corruption" "$__bandwidth_download"
    _add_route "$__ifb_dev" "$__src_ip" "$__dst_ip" "$__latency" "$__jitter" "$__packet_loss" "$__reorder" "$__duplication" "$__corruption" "$__bandwidth_upload"

    if _get_dev_qdisc "$__dev" "ingress"; then
        tc qdisc del dev "$__dev" ingress
    fi

    tc qdisc add dev "$__dev" ingress
    tc filter add dev "$__dev" ingress matchall action mirred egress redirect dev "$__ifb_dev"

    _log info "Added route from $__src_ip to $__dst_ip via $__dev"

}

_add_route() {
    __add_route_dev="$1"
    __add_route_src_ip="$2"
    __add_route_dst_ip="$3"
    __add_route_latency="$4"
    __add_route_jitter="$5"
    __add_route_packet_loss="$6"
    __add_route_reorder="$7"
    __add_route_duplication="$8"
    __add_route_corruption="$9"
    __add_route_bandwidth="${10}"

    __dev_qdisc=$(_get_dev_qdisc "$__dev" "root")
    if [ "$__dev_qdisc" != "htb" ]; then
        _log warn "Interface $__add_route_dev has qdisc $__dev_qdisc associated with it"
        echo "Do you want to continue? All qdisc from interface $__add_route_dev will be deleted [y|n]"
        read -r __continue
        if [ "$__continue" != "y" ]; then
            echo "Aborting tc-easy"
        fi
    fi

    # TODO: Os parâmetros do NetEm devem ser mirrored?
    # Quero dizer: se temos 10 de latência, seriam 5ms outgoing e 5ms incoming, totalizando 10ms
    # Ou 10ms outgoing e 10ms incoming, totalizando 20ms
    __add_route_netem_params=""
    if [ -n "$__add_route_latency" ]; then
        __add_route_netem_params="$__add_route_netem_params delay ${__add_route_latency}ms"
        # TODO: Checar se setando o jitter > latencia o TC buga
        if [ -n "$__add_route_jitter" ]; then
            __add_route_netem_params="$__add_route_netem_params ${__add_route_jitter}ms distribution normal"
        fi
    fi

    if [ -n "$__add_route_packet_loss" ]; then
        __add_route_netem_params="$__add_route_netem_params loss ${__add_route_packet_loss}%"
    fi

    if [ -n "$__add_route_reorder" ]; then
        __add_route_netem_params="$__add_route_netem_params reorder ${__add_route_reorder}%"
    fi

    if [ -n "$__add_route_duplication" ]; then
        __add_route_netem_params="$__add_route_netem_params reorder ${__add_route_duplication}%"
    fi

    if [ -n "$__add_route_corruption" ]; then
        __add_route_netem_params="$__add_route_netem_params corrupt ${__add_route_corruption}%"
    fi

    tc qdisc del dev "$__add_route_dev" root >/dev/null 2>&1

    # TODO: Arrumar os handles do qdisc, começando em 0
    # TODO: Adicionar fifo_fast como classe default do htb
    # TODO: Se houver outro qdisc como root, perguntar para o usuario o que fazer
    # TODO: Limitar a banda do root como a

    __dev_speed=$(cat /sys/class/net/"$__add_route_dev"/speed >/dev/null 2>&1)
    if [ -z "$__dev_speed" ] || [ "$__dev_speed"  -lt 0 ]; then
        _log "warn" "Cannot get $__add_route_dev speed, assuming 1000mbps"
        __dev_speed="1000"
    fi

    tc qdisc add dev "$__add_route_dev" root handle 1: htb

    # TODO: A banda máxima de download/upload deve ser sempre simétrica?
    tc class add dev "$__add_route_dev" parent 1: classid 1:1 htb rate "$__dev_speed"mbit ceil "$__dev_speed"mbit

    # TODO: checar se há banda disponível para a classe
    __add_route_bandwidth=${__add_route_bandwidth:-"50"}
    # Se não houver banda disponível, perguntar quando alocar e checar se o valor fornecido é menor que o máximo disponível (speed da interface - soma de todas as rates dos HTBs)
    tc class add dev "$__add_route_dev" parent 1:1 classid 1:10 htb rate "$__add_route_bandwidth"mbit ceil "$__add_route_bandwidth"mbit prio 2

    if [ -n "$__add_route_netem_params" ]; then
        # Remove trailing whitespaces, otherwhise TC does not accept __add_route_netem_params
        __add_route_netem_params=$(echo "$__add_route_netem_params" | cut -f 2- -d ' ')
        tc qdisc add dev "$__add_route_dev" parent 1:10 handle 10:1 netem $__add_route_netem_params
    fi

    # TODO: Checar se o __src_ip/__dst_ip são IPv4 Válido
    tc filter add dev "$__add_route_dev" protocol ip parent 1: prio 2 u32 match ip src "$__add_route_src_ip" match ip dst "$__add_route_dst_ip" flowid 1:10
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

    _log info "Removed route from $__src_ip to $__dst_ip via $__dev"

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
                _parse_args_add "$@"
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
                _log 'warn' "Unknown subcommand: $1, avaible subcommands are: add, rm and ls"
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
    _log "IFB kernel module is deactivated, try to activate it? [y|n]"
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
    _log "HTB kernel module is deactivated, try to activate it? [y|n]"
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

if ! _check_kmod_enabled "netem"; then
    _log "NetEm kernel module is deactivated, try to activate it? [y|n]"
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