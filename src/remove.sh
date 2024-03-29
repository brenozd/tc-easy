#!/bin/sh

. utils.sh

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
        printf "%s\n" "Are you sure you want to remove all routes from interface $__rm_route_dev and $__rm_route_ifb_dev? [y|n]"
        read -r __continue
        if [ "$__continue" != "y" ]; then
            printf "Aborting tc-easy\n"
            return 1
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

    if ! _is_ipv4_str_valid "$__args_rm_src_ip" || ! _is_ipv4_valid "$__args_rm_dst_ip"; then
        _log "error" "Either source or destination IP is not a valid IPv4"
        return
    fi

    if _get_route "$__rm_route_dev" "$__rm_route_src_ip" "$__rm_route_dst_ip"; then
        __rm_route_filter_handle=$(tc filter show dev "$__rm_route_dev" | grep "flowid $__g_route_flow_handle" | sed -n -e "s/^.*fh 800::\([0-9]\{3\}\).*$/\1/p")
        tc filter del dev "$__rm_route_dev" parent 1: handle 800::"$__rm_route_filter_handle" prio 2 protocol ip u32
        if tc qdisc show dev "$__rm_route_dev" | grep -q "parent $__g_route_flow_handle"; then
            tc qdisc del dev "$__rm_route_dev" parent "$__g_route_flow_handle"
        fi
        tc class del dev "$__rm_route_dev" classid "$__g_route_flow_handle"
    elif _get_route "$__rm_route_ifb_dev" "$__rm_route_src_ip" "$__rm_route_dst_ip"; then
        __rm_route_filter_handle=$(tc filter show dev "$__rm_route_ifb_dev" | grep "flowid $__g_route_flow_handle" | sed -n -e "s/^.*fh 800::\([0-9]\{3\}\).*$/\1/p")
        tc filter del dev "$__rm_route_ifb_dev" parent 1: handle 800::"$__rm_route_filter_handle" prio 2 protocol ip u32
        if tc qdisc show dev "$__rm_route_ifb_dev" | grep -q "parent $__g_route_flow_handle"; then
            tc qdisc del dev "$__rm_route_ifb_dev" parent "$__g_route_flow_handle"
        fi
        tc class del dev "$__rm_route_ifb_dev" classid "$__g_route_flow_handle"
    else
        _log "error" "Route from $__args_rm_src_ip to  $__args_rm_dst_ip via $__args_rm_dev does not exists"
    fi
}


