#!/usr/bin/env sh


# Global Variables
__g_force_cmd=0
__g_log_level=3

# Global return variables
__g_ip_string=""
__g_ip_hex=""
__g_dev_qdisc=""
__g_routes=""
__g_route_flow_handle=""
__g_route_bandwidth=""
__g_route_latency=""
__g_route_jitter=""
__g_route_loss=""

_log() {
    __log_level=0
    case $1 in
        error)
            __log_tag="ERROR"
            __redirect="2"
            __log_level=0
        ;;
        warn)
            __log_tag="WARN"
            __redirect="2"
            __log_level=1
        ;;
        info)
            __log_tag="INFO"
            __redirect="1"
            __log_level=2
        ;;
        debug)
            __log_tag="DEBUG"
            __redirect="1"
            __log_level=3
        ;;
    esac

    if [ "$__g_log_level" -gt "$__log_level" ]; then
        printf '%s - [%s] - %s\n' "$(date)" "$__log_tag" "$2"
    fi
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

# Check if a given IP/CIDR is a valid IPv4 construction (do not check if values are greater than 255 tho)
_is_ipv4_valid() {
    __is_ipv4_valid_ip=$(echo "$1" | sed -n -e 's/^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}\(\/[0-3][0-9]\?\)\?$/\0/p')
    if [ -z "$__is_ipv4_valid_ip" ]; then
        return 1
    fi
    return 0
}

# Utilizar modprobe para habilitar os módulos utilizados
_check_kmod_enabled() {
    module_state=$(awk -v mod="$1" '$1 ~mod {print $5}' /proc/modules)
    if [ "$module_state" = "Live" ]; then
        return 0
    fi
    return 1
}

_check_if_interface_exists() {
    interfaces=$(ls /sys/class/net)
    for i in $interfaces; do
        if [ "$1" = "$i" ]; then
            return 0
        fi
    done
    return 1
}

# Get a route
#   $1 is the interface (device) name
#   $2 is the src ip
#   $3 is the dst ip
#
# If src ip and dst ip are provided returns 0 if routes exits, 1 otherwhise.
#   Sets __g_route_flow_handle to the flow handle id if return 0
# If src ip and dst ip are empty, return 0 if dev has any route and set __g_routes
#   __g_routes is a variable that contain a triplet per route: src_ip dst_ip flow_id
_get_route() {
    __get_route_rc=1
    __get_route_dev="$1"
    __get_route_src_ip="$2"
    __get_route_dst_ip="$3"

    __get_route_dev_routes=$(tc filter show dev "$__get_route_dev")
    __get_route_flow_handle=""
    __g_routes=""
    __get_route_old_ifs=$IFS
    IFS="
"

    for line in $__get_route_dev_routes; do
        case $line in
            # If line is a filter definition, get handle
            "filter"*)
                __get_route_flow_handle=$(echo "$line" | sed -n -e 's/^.*\([0-9]\+:[0-9]\+\).*/\1/p')
                __get_route_src_ip_filter=""
                __get_route_dst_ip_filter=""
            ;;
            *"match"*"at 12")
                # TODO: O argumento depois do / é a máscara do CIDR se houver, neste caso o precisamos checar se o CIDR é igual ao setado no __get_route_src_ip ou __get_route_dst_ip.
                # TODO: caso nenhum mask esteja setado considerar /32

                __get_route_src_ip_filter=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
            ;;
            *"match"*"at 16")
                __get_route_dst_ip_filter=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
            ;;
        esac

        if  [ -n "$__get_route_flow_handle" ]     && \
            [ -n "$__get_route_src_ip_filter" ]   && \
            [ -n "$__get_route_dst_ip_filter" ]; then

            _ip_hex_to_string $__get_route_src_ip_filter
            __get_route_src_ip_filter="$__g_ip_string"
            _ip_hex_to_string $__get_route_dst_ip_filter
            __get_route_dst_ip_filter="$__g_ip_string"

            __g_routes="$__g_routes $__get_route_src_ip_filter $__get_route_dst_ip_filter $__get_route_flow_handle"
            if  [ -n "$__get_route_src_ip" ] && [ -n "$__get_route_dst_ip" ] && \
                [ "$__get_route_src_ip" = "$__get_route_src_ip_filter" ] && \
                [ "$__get_route_dst_ip" = "$__get_route_dst_ip_filter" ]; then

                __g_route_flow_handle=$__get_route_flow_handle
                __g_routes="$__get_route_src_ip_filter $__get_route_dst_ip_filter $__get_route_flow_handle"
                __get_route_rc=0
                break
            fi
        fi
    done
    IFS=$__get_route_old_ifs

    if [ -z "$__get_route_src_ip" ] && [ -z "$__get_route_dst_ip" ] && [ -n "$__g_routes" ]; then
        __get_route_rc=0
    fi
    return $__get_route_rc
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
    printf "Usage: tc-easy add dev <interface> from <ip> to <ip> OPTIONS\n"
    printf "Options:\n\t--latency <value>\n\t--loss <value>\n\t--jitter <value> (only used if --latency is passed)\n\t--download <value>\n\t--upload <value>\n"
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
                __args_add_latency="$1"
                shift
                ;;
            --jitter|-j)
                shift
                __args_add_jitter="$1"
                shift
                ;;
            --loss|-p)
                shift
                __args_add_packet_loss="$1"
                shift
                ;;         # Handle
            --reorder|-r)
                shift
                __args_add_reorder="$1"
                shift
                ;;
            --duplication)
                shift
                __args_add_duplication="$1"
                shift
                ;;
            --corruption|-c)
                shift
                __args_add_corruption="$1"
                shift
                ;;
                # TODO: Pq o download está indo para o upload e o upload está indo para o download? Troquei o nome das variáveis?
            --download|-d)
                shift
                __args_add_bandwidth_upload="$1"
                shift
                ;;
            --upload|-u)
                shift
                __args_add_bandwidth_download="$1"
                shift
                ;;
            -?*)
                _log "error" "Unknown add option: $1"
                _show_help_add
                return
                ;;
            *)
                break
        esac
    done

    __args_add_rc=0
    # TODO: Antes de fazer qualquer coisa checar se há banda disponível no TC
    if [ -z "$__args_add_dev" ] || [ -z "$__args_add_src_ip" ] || [ -z "$__args_add_dst_ip" ]; then
        _show_help_add
        return 1
    fi

    if ! _is_ipv4_valid "$__args_add_src_ip" || ! _is_ipv4_valid "$__args_add_dst_ip"; then
        _log "error" "Either source or destination IP is not a valid IPv4"
        return 1
    fi

    # TODO: Deveriamos sempre ter que setar o sentido, sendo download ou upload e poder especificar uma banda
    if [ -n "$__args_add_bandwidth_download" ] && \
        ! _add_route "$__args_add_dev" "$__args_add_src_ip" "$__args_add_dst_ip" \
        "$__args_add_latency" "$__args_add_jitter" "$__args_add_packet_loss" \
        "$__args_add_reorder" "$__args_add_duplication" "$__args_add_corruption" \
        "$__args_add_bandwidth_download"; then
        _log "error" "Failed to add route from $__args_add_src_ip to $__args_add_dst_ip via $__args_add_dev"
        __args_add_rc=1

    fi

    if [ -n "$__args_add_bandwidth_upload" ]; then
        __ifb_dev="ifb_$__args_add_dev"
        if ! _check_if_interface_exists "$__ifb_dev"; then
            ip link add name "$__ifb_dev" type ifb
        fi
        ip link set dev "$__ifb_dev" up

        if ! _add_route "$__ifb_dev" "$__args_add_dst_ip" "$__args_add_src_ip" \
        "$__args_add_latency" "$__args_add_jitter" "$__args_add_packet_loss" \
        "$__args_add_reorder" "$__args_add_duplication" "$__args_add_corruption" \
        "$__args_add_bandwidth_upload"; then
            _log "error" "Failed to add route from $__args_add_dst_ip to $__args_add_src_ip via $__args_add_dev"
            __args_add_rc=1
        fi

        if _get_dev_qdisc "$__args_add_dev" "ingress"; then
            tc qdisc del dev "$__args_add_dev" ingress
        fi

        tc qdisc add dev "$__args_add_dev" ingress
        tc filter add dev "$__args_add_dev" ingress matchall action mirred egress redirect dev "$__ifb_dev"
    fi

    if [ $__args_add_rc -eq 0 ]; then
        _log "info" "Added route from $__args_add_src_ip to $__args_add_dst_ip via $__args_add_dev"
    fi
    return $__args_add_rc
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

    if _get_route "$__add_route_dev" "$__add_route_src_ip" "$__add_route_dst_ip"; then
        _log "error" "Route from $__add_route_src_ip to  $__add_route_dst_ip via $__add_route_dev already exists (flow $__g_route_flow_handle)"
        return 1
    fi

    if _get_dev_qdisc "$__add_route_dev" "root" && [ "$__g_dev_qdisc" != "htb" ]; then
        if [ $__g_force_cmd -ne 1 ] &&  [ "$__continue" != "y" ]; then
            _log "warn" "Interface $__add_route_dev has qdisc $__g_dev_qdisc associated with it"
            printf "%s\n" "Do you want to continue? All qdisc from interface $__add_route_dev will be deleted [y|n]"
            read -r __continue
            if [ "$__continue" != "y" ]; then
                printf "Aborting tc-easy\n"
                return 1
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
            __add_route_netem_params="$__add_route_netem_params ${__add_route_jitter}ms distribution paretonormal"
        fi
      else
        # If no latency was set, use 3ms as default, which seens reasonable for a local network
        # This will be used to calculate the netem limit later
        __add_route_latency="3"
    fi

    if [ -n "$__add_route_packet_loss" ]; then
        __add_route_netem_params="$__add_route_netem_params loss ${__add_route_packet_loss}%"
    fi

    if [ -n "$__add_route_reorder" ]; then
        __add_route_netem_params="$__add_route_netem_params reorder ${__add_route_reorder}%"
    fi

    if [ -n "$__add_route_duplication" ]; then
        __add_route_netem_params="$__add_route_netem_params duplicate ${__add_route_duplication}%"
    fi

    if [ -n "$__add_route_corruption" ]; then
        __add_route_netem_params="$__add_route_netem_params corrupt ${__add_route_corruption}%"
    fi

    # TODO: checar se há banda disponível para a classe
    __add_route_new_handle=$(tc class show dev "$__add_route_dev" | grep htb | awk '{print $3}' | sort | tail -n1 | awk -F ':' '{print $2+1}')
    __add_route_bandwidth=${__add_route_bandwidth:-"50"}
    # Se não houver banda disponível, perguntar quando alocar e checar se o valor fornecido é menor que o máximo disponível (speed da interface - soma de todas as rates dos HTBs)
    tc class add dev "$__add_route_dev" parent 1:1 classid 1:"$__add_route_new_handle" htb rate "$__add_route_bandwidth"mbit ceil "$__add_route_bandwidth"mbit prio 0

    if [ -n "$__add_route_netem_params" ]; then
        __t_dev_mtu=$(cat "/sys/class/net/${__add_route_dev}/mtu")
        __add_route_mtu_dev=${__t_dev_mtu:-1500}
        # According to this SO answer, we should add 50% more lmit than the max packet rate * delay
        # https://stackoverflow.com/a/38277940
        __add_route_netem_limit=$(echo "$__add_route_bandwidth * 1000 * 1000 * ($__add_route_latency / 1000) / ($__add_route_mtu_dev * 8) * 1.5" | bc)

        # Remove trailing whitespaces, otherwhise TC does not accept __add_route_netem_params
        __add_route_netem_params=$(echo "$__add_route_netem_params" | cut -f 2- -d ' ')
        tc qdisc add dev "$__add_route_dev" parent 1:"$__add_route_new_handle" handle "$__add_route_new_handle":1 netem limit "$__add_route_netem_limit" $__add_route_netem_params
    fi

    tc filter add dev "$__add_route_dev" protocol ip parent 1: prio 0 u32 match ip src "$__add_route_src_ip" match ip dst "$__add_route_dst_ip" flowid 1:"$__add_route_new_handle"
}

_show_help_rm() {
    printf "Usage: tc-easy rm dev <interface> from <ip> to <ip>\n"
}

_parse_args_rm() {
    while :; do
        case $1 in
            -h|-\?|--help)   # Call a "show_help" function to display a synopsis, then exit.
                _show_help_rm
                exit
                ;;
            -f|--froce)
                __g_force_cmd=1
                shift
                ;;
            dev)
                shift
                _check_if_interface_exists "$1" || return
                __args_rm_dev="$1"
                shift
                ;;
            from)
                shift
                __args_rm_src_ip="$1"
                shift
                ;;
            to)
                shift
                __args_rm_dst_ip="$1"
                shift
                ;;
            -?*)
                _log "error" "Unknown add option: $1"
                _show_help_rm
                ;;
            *)
                break
        esac
    done

    if [ -z "$__args_rm_dev" ]; then
        _show_help_rm
        return
    fi

    _remove_route "$__args_rm_dev" "$__args_rm_src_ip" "$__args_rm_dst_ip"

    return

}

_remove_route() {
    __rm_route_dev="$1"
    __rm_route_src_ip="$2"
    __rm_route_dst_ip="$3"
    __rm_route_ifb_dev="ifb_$__rm_route_dev"

    if [ -z "$__rm_route_src_ip" ] && [ -z "$__rm_route_dst_ip" ]; then
        if [ $__g_force_cmd -ne 1 ]; then
          printf "%s\n" "Are you sure you want to remove all routes from interface $__rm_route_dev and $__rm_route_ifb_dev? [y|n]"
          read -r __continue
          if [ "$__continue" != "y" ]; then
              printf "Aborting tc-easy\n"
              return 1
          fi
        fi
        tc qdisc del dev "$__rm_route_dev" root >/dev/null 2>&1

        if _get_dev_qdisc "$__rm_route_dev" "ingress"; then
            tc qdisc del dev "$__rm_route_dev" ingress >/dev/null 2>&1
        fi

        if _check_if_interface_exists "$__rm_route_ifb_dev"; then
            ip link delete "$__rm_route_ifb_dev"
        fi

        _log "info" "Removed all routes from $__args_rm_dev"
        return 0
    fi

    if ! _is_ipv4_valid "$__args_rm_src_ip" || ! _is_ipv4_valid "$__args_rm_dst_ip"; then
        _log "error" "Either source or destination IP is not a valid IPv4"
        return
    fi

    if _get_route "$__rm_route_dev" "$__rm_route_src_ip" "$__rm_route_dst_ip"; then
        __rm_route_filter_handle=$(tc filter show dev "$__rm_route_dev" | grep "flowid $__g_route_flow_handle" | sed -n -e "s/^.*fh 800::\([0-9]\{3\}\).*$/\1/p")
        tc filter del dev "$__rm_route_dev" parent 1: handle 800::"$__rm_route_filter_handle" prio 0 protocol ip u32
        if tc qdisc show dev "$__rm_route_dev" | grep -q "parent $__g_route_flow_handle"; then
            tc qdisc del dev "$__rm_route_dev" parent "$__g_route_flow_handle"
        fi
        tc class del dev "$__rm_route_dev" classid "$__g_route_flow_handle"
    elif _get_route "$__rm_route_ifb_dev" "$__rm_route_src_ip" "$__rm_route_dst_ip"; then
        __rm_route_filter_handle=$(tc filter show dev "$__rm_route_ifb_dev" | grep "flowid $__g_route_flow_handle" | sed -n -e "s/^.*fh 800::\([0-9]\{3\}\).*$/\1/p")
        tc filter del dev "$__rm_route_ifb_dev" parent 1: handle 800::"$__rm_route_filter_handle" prio 0 protocol ip u32
        if tc qdisc show dev "$__rm_route_ifb_dev" | grep -q "parent $__g_route_flow_handle"; then
            tc qdisc del dev "$__rm_route_ifb_dev" parent "$__g_route_flow_handle"
        fi
        tc class del dev "$__rm_route_ifb_dev" classid "$__g_route_flow_handle"
    else
        _log "error" "Route from $__args_rm_src_ip to  $__args_rm_dst_ip via $__args_rm_dev does not exists"
    fi
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
                __args_ls_dev="$1"
                shift
                ;;
            from)
                shift
                __args_ls_src_ip="$1"
                shift
                ;;
            to)
                shift
                __args_ls_dst_ip="$1"
                shift
                ;;
            -?*)
                _log "error" "Unknown add option: $1"
                _show_help_ls
                ;;
            *)
                break
        esac
    done

    if [ -z "$__args_ls_dev" ]; then
        _show_help_ls
        return
    fi

    printf "%-16s%-15s%-20s%-15s%-15s%-15s%-15s\n" "Device" "Source IP" "Destination IP" "Bandwidth" "Latency" "Jitter" "Packet Loss"
    _list_routes "$__args_ls_dev" "$__args_ls_src_ip" "$__args_ls_dst_ip"

    if _check_if_interface_exists "ifb_$__args_ls_dev"; then
        _list_routes "ifb_$__args_ls_dev" "$__args_ls_src_ip" "$__args_ls_dst_ip"
    fi
}

_get_flow_parameters() {
    __get_flow_dev="$1"
    __get_flow_id="$2"

    __get_flow_old_ifs=$IFS
    IFS="
"
    __get_flow_dev_class=$(tc class show dev "$__get_flow_dev" | grep "htb $__get_flow_id parent 1:1")
    __get_flow_dev_class_id=$(echo "$__get_flow_dev_class" | awk '{print $3}')
    __get_flow_netem=$(tc qdisc show dev "$__get_flow_dev" | grep "netem" | grep "parent $__get_flow_dev_class_id")
    __g_route_bandwidth=$(echo "$__get_flow_dev_class" | sed -n -e "s/^.*rate \([0-9]\+[a-zA-Z]\+\).*$/\1/p")
    __g_route_latency=$(echo "$__get_flow_netem" | sed -n -e "s/^.*delay \([0-9]\+[a-zA-Z]\+\).*$/\1/p")
    __g_route_jitter=$(echo "$__get_flow_netem" | sed -n -e "s/^.*delay \([0-9]\+[a-zA-Z]\+\)\s*\([0-9]\+[a-zA-Z]\+\).*$/\2/p")
    __g_route_loss=$(echo "$__get_flow_netem" | sed -n -e "s/^.*loss \([0-9]\+\)%.*$/\1/p")

    __g_route_bandwidth=${__g_route_bandwidth:-"-"}
    __g_route_latency=${__g_route_latency:-"-"}
    __g_route_jitter=${__g_route_jitter:-"-"}
    __g_route_loss=${__g_route_loss:-"-"}

    IFS=$__get_flow_old_ifs
}

_list_routes() {
    __list_route_dev="$1"
    __list_route_src_ip="$2"
    __list_route_dst_ip="$3"

    if _get_dev_qdisc "$__list_route_dev" "root" && [ "$__g_dev_qdisc" != "htb" ]; then
        _log "info" "No routes on dev $__list_route_dev"
        return 1
    fi

    if ! _get_route "$__list_route_dev" "$__list_route_src_ip" "$__list_route_dst_ip"; then
        _log "debug" "Route from $__list_route_src_ip to $__list_route_dst_ip via $__list_route_dev does not exists!"
        return 1
    fi

    _list_routes_length=$(echo "$__g_routes" | wc -w)
    _list_routes_index=0
    while [ "$_list_routes_index" -lt "$_list_routes_length" ]; do
        # item=$(echo "$__g_routes" | awk -v i=$((_list_routes_index+1)) '{print $i}')
        # echo "$item"
        __list_route_print_src_ip=$(echo "$__g_routes" | awk -v i=$((_list_routes_index+1)) '{print $i}')
        __list_route_print_dst_ip=$(echo "$__g_routes" | awk -v i=$((_list_routes_index+2)) '{print $i}')
        __list_route_flowid=$(echo "$__g_routes" | awk -v i=$((_list_routes_index+3)) '{print $i}')
        _get_flow_parameters "$__list_route_dev" "$__list_route_flowid"
        printf "%-16s%-15s%-20s%-15s%-15s%-15s%-15s\n" \
                "$__list_route_dev" \
                "$__list_route_print_src_ip" \
                "$__list_route_print_dst_ip" \
                "$__g_route_bandwidth" \
                "$__g_route_latency" \
                "$__g_route_jitter" \
                "$__g_route_loss"
        _list_routes_index=$((_list_routes_index + 3))
    done
}

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
            -f|--froce)
                __g_force_cmd=1
                shift
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
