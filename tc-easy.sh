#!/usr/bin/env sh

# set -e
# set -x

# Global Variables
__g_force_cmd=0

# Global return variables
__g_ip_string=""
__g_ip_hex=""
__g_dev_qdisc=""

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

# Convert an formated IPv4 string to hexadecimal. Return value is variable __g_ip_hex
_ip_string_to_hex() {
    __s2h_ip="$1"
    __g_ip_hex=""
    __s2h_old_IFS="$IFS"
    IFS="."
    for num in $__s2h_ip; do
        __g_ip_hex="$__g_ip_hex$(printf "%02x" "$num")"
    done
    IFS=$__s2h_old_IFS
}

# Convert an hexadecimal IPv4 to a formatted string. Return value is variable __g_ip_string
_ip_hex_to_string() {
    __h2s_hex=$(echo "$1" | sed 's/.\{2\}/& /g')
    __g_ip_string=""

    _ip_h2s_old_IFS=$IFS
    IFS=" "
    for hex in $__h2s_hex; do
        __g_ip_string="$__g_ip_string$(printf "%d" "0x$hex")."
    done
    IFS=$_ip_h2s_old_IFS
    __g_ip_string=$(echo "$__g_ip_string" | cut -d'.' -f 1,2,3,4)
}

# Check if a given IP is a valid IPv4 construction (do not check if values are greater than 255 tho)
_is_ipv4_valid() {
    __is_ipv4_valid_ip=$(echo "$1" | sed -n -e 's/^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}$/\0/p')
    if [ -z "$__is_ipv4_valid_ip" ]; then
        return 1
    fi
    return 0
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

# Gets the current qdisc associated with dev at classid. Return value is variable __g_dev_qdisc
_get_dev_qdisc() {
    __get_dev_qdisc_dev="$1"
    __get_dev_qdisc_classid="$2"
    __get_dev_qdisc_root_qdisc=$(tc qdisc show dev "$__get_dev_qdisc_dev" "$__get_dev_qdisc_classid")
    if [ -z "$__get_dev_qdisc_root_qdisc" ]; then
        return 1
    fi
    __g_dev_qdisc=$(echo "$__get_dev_qdisc_root_qdisc" | awk '{print $2}')
    return 0
}

_show_help_add() {
    echo "Usage: tc-easy add dev <interface> from <ip> to <ip> OPTIONS"
    printf "Options:\n\t--latency=<value>\n\t--loss=<value>\n\t--jitter=<value> (only used if --latency is passed)\n\t--download=<value>\n\t--upload=<value>\n"
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
                __args_add_dev="$1"
                shift
                ;;
            from)
                shift
                __args_add_src_ip="$1"
                shift
                ;;
            to)
                shift
                __args_add_dst_ip="$1"
                shift
                ;;
            -f|--froce)
                __g_force_cmd=1
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
            --loss|-p)
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
                return
                ;;
            *)
                break
        esac
    done

    # TODO: Antes de fazer qualquer coisa checar se há banda disponível no TC
    if [ -z "$__args_add_dev" ] || [ -z "$__args_add_src_ip" ] || [ -z "$__args_add_dst_ip" ]; then
        _show_help_add
        return
    fi

    if ! _is_ipv4_valid "$__args_add_src_ip" || ! _is_ipv4_valid "$__args_add_dst_ip"; then
        _log "error" "Either source or destination IP is no a valid IPv4"
        return
    fi

    # Check if route already exists
    __args_add_interface_routes=$(tc filter show dev "$__args_add_dev")
    __args_add_flow_handle=""
    __args_add_old_IFS=$IFS
    IFS="
"
    for line in $__args_add_interface_routes; do
        case $line in
            # If line is a filter definition, get handle
            "filter"*)
                __args_add_flow_handle=$(echo "$line" | sed -n -e 's/^.*\([0-9]\+:[0-9]\+\).*/\1/p')
                __args_add_src_ip_filter=""
                __args_add_dst_ip_filter=""
            ;;
            *"match"*"at 12")
                # TODO: checar o que é o argumento depois do / no IP
                __args_add_src_ip_filter=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
            ;;
            *"match"*"at 16")
                __args_add_dst_ip_filter=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
            ;;
        esac

        if [ -n "$__args_add_flow_handle" ] && [ -n "$__args_add_src_ip_filter" ] && [ -n "$__args_add_dst_ip_filter" ]; then
            _ip_hex_to_string $__args_add_src_ip_filter
            __args_add_src_ip_filter="$__g_ip_string"

            _ip_hex_to_string $__args_add_dst_ip_filter
            __args_add_dst_ip_filter="$__g_ip_string"

            # TODO: Ao invés de abortar, perguntar ao usuário se deseja alterar a rota
            # TODO: Imprimir informações da rota
            if [ "$__args_add_src_ip" = "$__args_add_src_ip_filter" ] && [ "$__args_add_dst_ip" = "$__args_add_dst_ip_filter" ]; then
                _log "warn" "Route from $__args_add_src_ip_filter to $__args_add_dst_ip_filter already exists (flowid $__args_add_flow_handle), aborting!\n"
                exit 10
            fi
        fi
    done
    IFS=$__args_add_old_IFS

    __ifb_dev="ifb_$__args_add_dev"
    if ! _check_if_interface_exists "$__ifb_dev"; then
        ip link add name "$__ifb_dev" type ifb
    fi
    ip link set dev "$__ifb_dev" up

    _add_route "$__args_add_dev"     "$__args_add_src_ip" "$__args_add_dst_ip" "$__latency" "$__jitter" "$__packet_loss" "$__reorder" "$__duplication" "$__corruption" "$__bandwidth_download"
    _add_route "$__ifb_dev" "$__args_add_src_ip" "$__args_add_dst_ip" "$__latency" "$__jitter" "$__packet_loss" "$__reorder" "$__duplication" "$__corruption" "$__bandwidth_upload"

    if _get_dev_qdisc "$__args_add_dev" "ingress"; then
        tc qdisc del dev "$__args_add_dev" ingress
    fi

    tc qdisc add dev "$__args_add_dev" ingress
    tc filter add dev "$__args_add_dev" ingress matchall action mirred egress redirect dev "$__ifb_dev"

    _log "info" "Added route from $__args_add_src_ip to $__args_add_dst_ip via $__args_add_dev"
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


    if _get_dev_qdisc "$__add_route_dev" "root" && [ "$__g_dev_qdisc" != "htb" ]; then
        if [ $__g_force_cmd -ne 1 ] &&  [ "$__continue" != "y" ]; then
            _log warn "Interface $__add_route_dev has qdisc $__g_dev_qdisc associated with it"
            echo "Do you want to continue? All qdisc from interface $__add_route_dev will be deleted [y|n]"
            read -r __continue
            if [ "$__continue" != "y" ]; then
                echo "Aborting tc-easy"
                return
            fi
        fi
        tc qdisc del dev "$__add_route_dev" root >/dev/null 2>&1
        tc qdisc add dev "$__add_route_dev" root handle 1: htb
        # TODO: A banda máxima de download/upload deve ser sempre simétrica?
        # TODO: Adicionar fifo_fast como classe default do htb
        __add_route_dev_speed=$(cat /sys/class/net/"$__add_route_dev"/speed >/dev/null 2>&1)
        if [ -z "$__add_route_dev_speed" ] || [ "$__add_route_dev_speed"  -lt 0 ]; then
            _log "warn" "Cannot get $__add_route_dev speed, assuming 1000mbps"
            __add_route_dev_speed="1000"
        fi
        tc class add dev "$__add_route_dev" parent 1: classid 1:1 htb rate "$__add_route_dev_speed"mbit ceil "$__add_route_dev_speed"mbit
    fi

    # TODO: Os parâmetros do NetEm devem ser mirrored?
    # Quero dizer: se temos 10 de latência, seriam 5ms outgoing e 5ms incoming, totalizando 10ms
    # Ou 10ms outgoing e 10ms incoming, totalizando 20ms
    __add_route_netem_params=""
    if [ -n "$__add_route_latency" ]; then
        __add_route_netem_params="$__add_route_netem_params delay ${__add_route_latency}ms"
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

    # TODO: checar se há banda disponível para a classe
    __add_route_new_handle=$(tc class show dev "$__add_route_dev" | grep htb | awk '{print $3}' | sort | tail -n1 | awk -F ':' '{print $2+1}')
    __add_route_bandwidth=${__add_route_bandwidth:-"50"}
    # Se não houver banda disponível, perguntar quando alocar e checar se o valor fornecido é menor que o máximo disponível (speed da interface - soma de todas as rates dos HTBs)
    tc class add dev "$__add_route_dev" parent 1:1 classid 1:"$__add_route_new_handle" htb rate "$__add_route_bandwidth"mbit ceil "$__add_route_bandwidth"mbit prio 2

    if [ -n "$__add_route_netem_params" ]; then
        # Remove trailing whitespaces, otherwhise TC does not accept __add_route_netem_params
        __add_route_netem_params=$(echo "$__add_route_netem_params" | cut -f 2- -d ' ')
        tc qdisc add dev "$__add_route_dev" parent 1:"$__add_route_new_handle" handle "$__add_route_new_handle":1 netem $__add_route_netem_params
    fi

    tc filter add dev "$__add_route_dev" protocol ip parent 1: prio 2 u32 match ip src "$__add_route_src_ip" match ip dst "$__add_route_dst_ip" flowid 1:"$__add_route_new_handle"
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

_show_help_ls() {
    printf "Usage: tc-easy ls dev <interface>\n"
    printf "Optional: from <ip>, to <ip>\n"
}

_parse_args_ls() {
    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_ls
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

    if [ -z "$__dev" ]; then
        _show_help_ls
        return
    fi

    _list_routes "$__dev"
}

_list_routes() {
    __list_route_dev="$1"
    __list_route_src_ip="$2"
    __list_route_dst_ip="$3"
    __list_routes_dev_qdiscs=$(tc qdisc show dev "$__list_route_dev")
    __list_routes_dev_classes=$(tc class show dev "$__list_route_dev")
    __list_routes_dev_filters=$(tc filter show dev "$__list_route_dev")


    printf "%s\n" "$__list_routes_dev_qdiscs"
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