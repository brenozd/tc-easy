#!/bin/sh

. "$PWD/utils.sh"

############################
## Show add subcomand help #
############################
_show_help_add() {
	printf "Usage: tc-easy add dev <interface> from <ip> to <ip> OPTIONS\n"
	printf "Options:\n\t--latency=<value>\n\t--loss=<value>\n\t--jitter=<value> (only used if --latency is passed)\n\t--download=<value>\n\t--upload=<value>\n"
}

#####################################
## Parse add subcomand flags        #
## Arguments:                       #
##   - The arguments to be parsed   #
#####################################
_parse_args_add() {
	while :; do
		case $1 in
		-h | -\? | --help) # Call a "show_help" function to display a synopsis, then exit.
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
		-f | --froce)
			__g_force_cmd=1
			shift
			;;
		--latency | -l)
			shift
			__args_add_latency="$1"
			shift
			;;
		--jitter | -j)
			shift
			__args_add_jitter="$1"
			shift
			;;
		--loss | -p)
			shift
			__args_add_packet_loss="$1"
			shift
			;;
		--reorder | -r)
			shift
			__args_add_reorder="$1"
			shift
			;;
		--duplication)
			shift
			__args_add_duplication="$1"
			shift
			;;
		--corruption | -c)
			shift
			__args_add_corruption="$1"
			shift
			;;
			# TODO: Pq o download está indo para o upload e o upload está indo para o download? Troquei o gnome das variáveis?
		--download | -d)
			shift
			__args_add_bandwidth_upload="$1"
			shift
			;;
		--upload | -u)
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
			;;
		esac
	done

	# TODO: Antes de fazer qualquer coisa checar se há banda disponível no TC
	if [ "$__args_add_dev" = "" ] || [ "$__args_add_src_ip" = "" ] || [ "$__args_add_dst_ip" = "" ]; then
		_show_help_add
		return 1
	fi

	if ! _is_ipv4_str_valid "$__args_add_src_ip" || ! _is_ipv4_valid "$__args_add_dst_ip"; then
		_log "error" "Either source or destination IP is not a valid IPv4"
		return 1
	fi

	__args_add_rc=0
	if [ "$__args_add_bandwidth_download" != "" ] &&
		! _add_route "$__args_add_dev" "$__args_add_src_ip" "$__args_add_dst_ip" \
			"$__args_add_latency" "$__args_add_jitter" "$__args_add_packet_loss" \
			"$__args_add_reorder" "$__args_add_duplication" "$__args_add_corruption" \
			"$__args_add_bandwidth_download"; then
		_log "error" "Failed to add route from $__args_add_src_ip to $__args_add_dst_ip via $__args_add_dev"
		__args_add_rc=1
	fi

	if [ "$__args_add_bandwidth_upload" != "" ]; then
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

    # Redirect all incoming traffic to IFB
		tc qdisc add dev "$__args_add_dev" ingress
		tc filter add dev "$__args_add_dev" ingress matchall action mirred egress redirect dev "$__ifb_dev"
	fi

	if [ "$__args_add_rc" -eq 0 ]; then
		_log "info" "Added route from $__args_add_src_ip to $__args_add_dst_ip via $__args_add_dev"
	fi
	return "$__args_add_rc"
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

	if _get_flow_handle_for_route "$__add_route_dev" "$__add_route_src_ip" "$__add_route_dst_ip" "__l_route_flow_handle"; then
		_log "error" "Route from $__add_route_src_ip to  $__add_route_dst_ip via $__add_route_dev already exists (flow $__l_route_flow_handle)"
		return 1
	fi

	if _get_dev_qdisc "$__add_route_dev" "root" "_l_dev_qdisc" && [ "$__l_dev_qdisc" != "htb" ]; then
		if [ "$__g_force_cmd" -ne 1 ] && [ "$__continue" != "y" ]; then
			_log "warn" "Interface $__add_route_dev has qdisc $__l_dev_qdisc associated with it"
			printf "%s\n" "Do you want to continue? All qdisc from interface $__add_route_dev will be deleted [y|n]"
			read -r __continue
			if [ "$__continue" != "y" ]; then
				printf "Aborting tc-easy\n"
				return 1
			fi
		fi

		tc qdisc del dev "$__add_route_dev" root >/dev/null 2>&1
		tc qdisc add dev "$__add_route_dev" root handle 1: htb
		# TODO: A banda máxima de download/upload deve set sempre simétrica?
		# TODO: Adicionar fifo_fast como classe default do htb
		__add_route_dev_speed=$(cat /sys/class/net/"$__add_route_dev"/speed >/dev/null 2>&1)
		if [ "$__add_route_dev_speed" = "" ] || [ "$__add_route_dev_speed" -lt 0 ]; then
			_log "warn" "Cannot get $__add_route_dev speed, assuming 1000mbps"
			__add_route_dev_speed="1000"
		fi
		tc class add dev "$__add_route_dev" parent 1: classid 1:1 htb rate "$__add_route_dev_speed"mbit ceil "$__add_route_dev_speed"mbit
	fi

	# TODO: Os parâmetros do NetEm devem set mirrored?
	# Quero dizer: se temos 10 de latência, seriam 5ms outgoing e 5ms incoming, totalizando 10ms
	# Ou 10ms outgoing e 10ms incoming, totalizando 20ms
	__add_route_netem_params=""
	if [ "$__add_route_latency" != "" ]; then
		__add_route_netem_params="$__add_route_netem_params delay ${__add_route_latency}ms"
		if [ "$__add_route_jitter" != "" ]; then
			__add_route_netem_params="$__add_route_netem_params ${__add_route_jitter}ms"
		fi
	fi

	if [ "$__add_route_packet_loss" != "" ]; then
		__add_route_netem_params="$__add_route_netem_params loss ${__add_route_packet_loss}%"
	fi

	if [ "$__add_route_reorder" != "" ]; then
		__add_route_netem_params="$__add_route_netem_params reorder ${__add_route_reorder}%"
	fi

	if [ "$__add_route_duplication" != "" ]; then
		__add_route_netem_params="$__add_route_netem_params duplicate ${__add_route_duplication}%"
	fi

	if [ "$__add_route_corruption" != "" ]; then
		__add_route_netem_params="$__add_route_netem_params corrupt ${__add_route_corruption}%"
	fi

	# TODO: checar se há banda disponível para a classe
	__add_route_new_handle=$(tc class show dev "$__add_route_dev" | grep htb | awk '{print $3}' | sort | tail -n1 | awk -F ':' '{print $2+1}')
	__add_route_bandwidth=${__add_route_bandwidth:-"50"}
	# Se não houver banda disponível, perguntar quando alocar e checar se o valor fornecido é menor que o máximo disponível (speed da interface - soma de todas as rates dos HTBs)
	tc class add dev "$__add_route_dev" parent 1:1 classid 1:"$__add_route_new_handle" htb rate "$__add_route_bandwidth"mbit ceil "$__add_route_bandwidth"mbit prio 2

	if [ "$__add_route_netem_params" != "" ]; then
		# Remove trailing whitespaces, otherwise TC does not accept __add_route_netem_params
		__add_route_netem_params=$(echo "$__add_route_netem_params" | cut -f2- -d' ')
		tc qdisc add dev "$__add_route_dev" parent 1:"$__add_route_new_handle" handle "$__add_route_new_handle":1 netem $__add_route_netem_params
	fi

	tc filter add dev "$__add_route_dev" protocol ip parent 1: prio 2 u32 match ip src "$__add_route_src_ip" match ip dst "$__add_route_dst_ip" flowid 1:"$__add_route_new_handle"
}

# _add_route "wlp0s20f3" "10.24.30.7" "10.24.30.8" "100" "0" "0" "0" "0" "0" "10"
