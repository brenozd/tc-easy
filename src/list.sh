#!/bin/sh


. utils.sh
_get_flow_handle_for_route

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

    _list_routes_length=$(echo "$__l_routes" | wc -w)
    _list_routes_index=0
    while [ "$_list_routes_index" -lt "$_list_routes_length" ]; do
        # item=$(echo "$__g_routes" | awk -v i=$((_list_routes_index+1)) '{print $i}')
        # echo "$item"
        __list_route_print_src_ip=$(echo "$__l_routes" | awk -v i=$((_list_routes_index+1)) '{print $i}')
        __list_route_print_dst_ip=$(echo "$__l_routes" | awk -v i=$((_list_routes_index+2)) '{print $i}')
        __list_route_flowid=$(echo "$__l_routes" | awk -v i=$((_list_routes_index+3)) '{print $i}')
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

