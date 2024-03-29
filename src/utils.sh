#!/usr/bin/env sh

#########################################
## Controls the verbosity of the script #
## Used primarily in _log()             #
#########################################
__g_log_level=${__g_log_level:-2}

########################################################################## 
## Write an message to stdout or stderr appending the severity and time  #
## Globals:                                                              #
##   - __g_log_level                                                     #
## Arguments:                                                            #
##   - Severity                                                          #
##     - 0: ERROR (default)                                              #
##     - 1: WARN                                                         #
##     - 2: INFO                                                         #
##     - 3: DEBUG                                                        #
##########################################################################
_log() {
    __l_log_level=0
    case $1 in
        error)
            __log_tag="ERROR"
            __redirect="2"
            __l_log_level=0
        ;;
        warn)
            __log_tag="WARN"
            __redirect="2"
            __l_log_level=1
        ;;
        info)
            __log_tag="INFO"
            __redirect="1"
            __l_log_level=2
        ;;
        debug)
            __log_tag="DEBUG"
            __redirect="1"
            __l_log_level=3
        ;;
        *)
          printf '%s - [%s] - Unknown log level %s\n' "$(date)" "ERROR" "$1"
          return 1
          ;;

    esac

    if [ "$__g_log_level" -gt "$__l_log_level" ]; then
        printf '%s - [%s] - %s\n' "$(date)" "$__log_tag" "$2"
    fi
    return 0
}

############################################################
## Convert an formatted IPv4/CIDR string to hexadecimal    #
## Arguments:                                              #
##   - The CIDR representation of ip to be converted       #
##   - The variable name where to hex value will be stored #
############################################################
_ip_string_to_hex() {
    __l_s2h_ip="$1"
    __l_s2h_old_IFS="$IFS"
    __l_ip_hex=""
    IFS="."
    for num in $__l_s2h_ip; do
        __l_ip_hex="$__l_ip_hex$(printf "%02x" "$num")"
    done
    IFS=$__l_s2h_old_IFS
    eval "$2='$__l_ip_hex'"
    return 0
}

################################################################
## Convert an hexadecimal IPv4 to a formatted string           #
## Arguments:                                                  #
##   - The hexadecimal representation of ip to be converted    #
##   - The variable name where to string value will be stored  #
################################################################
_ip_hex_to_string() {
    __l_h2s_hex=$(echo "$1" | sed --quiet '1 s/\([0-9A-Fa-f]\{8\}\).*/\1/p')

    __l_ip_string=""
    __l_h2s_old_IFS=$IFS
    while [ "${#__l_h2s_hex}" -gt 0 ]; do
        __l_ip_string="$__l_ip_string$(printf "%d" "0x${__l_h2s_hex%${__l_h2s_hex#??}}")."
        __l_h2s_hex="${__l_h2s_hex#??}"
    done
    __l_ip_string=$(echo "$__l_ip_string" | cut -d'.' -f 1,2,3,4)

    if _is_ipv4_str_valid "$__l_ip_string"; then
      eval "$2='$__l_ip_string'"
      return 0
    fi
    return 1
}

############################################################
## Check if a given IP/CIDR is a valid IPv4 String         #
## Arguments:                                              #
##   - The string representation of ip to be converted     #
############################################################
_is_ipv4_str_valid() {
    __l_ipv4_regex="^\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}\(\/[0-3][0-9]\?\)\?$"
    __l_is_ipv4_valid=$(echo "$1" | sed -n -e "s/$__l_ipv4_regex/\0/p")
    if [ "$__l_is_ipv4_valid" = "" ]; then
        return 1
    fi
    IFS="."
    for num in $1; do
        if [ "$num" -lt 0 ] || [ "$num" -gt 255 ]; then
          return 1
        fi
    done
    return 0
}

#############################################################
## Check if a given IP/CIDR is a valid IPv4 Hex             #
## Arguments:                                               #
##   - The string representation of ip to be converted      #
#############################################################
_is_ipv4_hex_valid() {
    __l_ipv4_regex="^([0-9a-fA-F][0-9a-fA-F]){4}$"
    __l_is_ipv4_valid=$(echo "$1" | sed -n -e "s/$__l_ipv4_regex/\0/p")
    if [ "$__l_is_ipv4_valid" = "" ]; then
        return 1
    fi
    return 0
}

############################################################
## Check if a given kernel module is enabled and loaded    #
## Arguments:                                              #
##   - The name of the module to check                     #
############################################################
_check_kmod_enabled() {
    __l_module_state=$(awk -v mod="$1" '$1 ~mod {print $5}' /proc/modules)
    if [ "$__l_module_state" = "Live" ]; then
        return 0
    fi
    return 1
}

############################################################
## Check if a given network interface exists               #
## Arguments:                                              #
##   - The name of the network interface to check          #
############################################################
_check_if_interface_exists() {
    for i in /sys/class/net/*; do
        if [ "$1" = "$i" ]; then
            return 0
        fi
    done
    return 1
}

###################################################################
## Get a flow handle ID for an specific route determined by       #
## a src and dst ip                                               #
## Arguments:                                                     #
##  - The name of the interface in which the route may            #
##    be present                                                  #
##  - The source ip of route                                      #
##  - The destination ip of route                                 #
##  - The variable name where the flow handle ID will be stored   #
## Returns:                                                       #
##  - 0 if a route was found                                      #
##  - 1 if no route was found                                     #
###################################################################
_get_flow_handle_for_route() {
    __l_rc=1
    __l_dev="$1"
    __l_src_ip="$2"
    __l_dst_ip="$3"

    __l_dev_routes=$(tc filter show dev "$__l_dev")
    __l_route_flow_handle=""
    __l_old_ifs=$IFS
    IFS="
"

    for line in $__l_dev_routes; do
        case $line in
            # If line is a filter definition, get handle
            "filter"*)
                __l_route_flow_handle=$(echo "$line" | sed -n -e 's/^.*\([0-9]\+:[0-9]\+\).*/\1/p')
                __l_filter_src_ip=""
                __l_filter_dst_ip=""
            ;;
            *"match"*"at 12")
                # TODO: O argumento depois do / é a máscara do CIDR se houver, neste caso o precisamos checar se o CIDR é igual ao setado no __get_route_src_ip ou __get_route_dst_ip.
                # TODO: caso nenhum mask esteja setado considerar /32
                __l_filter_src_ip=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
                if ! _ip_hex_to_string "$__l_filter_src_ip" "__l_filter_src_ip"; then
                  __l_filter_src_ip=""
                fi
            ;;
            *"match"*"at 16")
                __l_filter_dst_ip=$(echo "$line" | sed -e 's/^.*\([abcdef0-9]\{8\}\/[abcdef0-9]\{8\}\).*/\1/p' | cut -d'/' -f1)
                if ! _ip_hex_to_string "$__l_filter_dst_ip" "__l_filter_dst_ip"; then
                  __l_filter_dst_ip=""
                fi
            ;;
        esac

        if  [ "$__l_src_ip" = "$__l_filter_src_ip" ] && \
            [ "$__l_dst_ip" = "$__l_filter_dst_ip" ]; then

            [ $# -ge 4 ] && eval "$4='$__l_route_flow_handle'"
            __l_rc=0
            break
        fi
    done
  
    IFS=$__l_old_ifs

    return "$__l_rc"
}

#############################################################
## Gets the current qdisc associated with dev at classid    #
## Arguments:                                               #
##  - The name of the interface in which the qdisc          #
##    may be present                                        #
##  - The class id of the qdisc                             #
##  - The variable name to store the device root qdisc name #
## Returns:                                                 #
##  - 0 if a qisc was found                                 #
##  - 1 if no qdisc was found                               #
#############################################################
_get_dev_qdisc() {
    __get_dev_qdisc_dev="$1"
    __get_dev_qdisc_classid="$2"
    __get_dev_qdisc_root_qdisc=$(tc qdisc show dev "$__get_dev_qdisc_dev" "$__get_dev_qdisc_classid")
    if [ "$__get_dev_qdisc_root_qdisc" = "" ]; then
        return 1
    fi
    
    __l_dev_qdisc=$(echo "$__get_dev_qdisc_root_qdisc" | awk '{print $2}')
    [ $# -ge 3 ] && eval "$3='$__l_dev_qdisc'"
    return 0
}
