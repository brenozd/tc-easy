#!/bin/sh

set -e
#set -x

test_time_seconds=${1:-30}
ping_packet_count=${2:-1000}

container_ip=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' iperf3)
if [ -z "$container_ip" ]; then
  printf "Cannot get iperf3 container IP" >&2i
  exit 1
fi

download_bandwidth=$(iperf3 -c $container_ip -t $test_time_seconds -Z -J | jq '.end.sum_received.bits_per_second')
upload_bandwidth=$(iperf3 -c $container_ip -t $test_time_seconds -Z -J -R | jq '.end.sum_received.bits_per_second')

ping_output=$(ping $container_ip -U -c $ping_packet_count -A | tail -n2)
avg_rtt=$(echo $ping_output | sed -n 's/^.*min\/avg\/max\/mdev = \([0-9.]\+\)\/\([0-9.]\+\)\/[0-9.]\+\/\([0-9.]\+\) ms.*$/\2/p')
jitter=$(echo $ping_output | sed -n 's/^.*min\/avg\/max\/mdev = \([0-9.]\+\)\/\([0-9.]\+\)\/[0-9.]\+\/\([0-9.]\+\) ms.*$/\3/p')
packet_loss=$(echo $ping_output | sed -n 's/^.* \([0-9]\+\)% packet loss.*$/\1/p')

printf "Download:%14s Mbps\n" $(echo "scale=2; $download_bandwidth / 1000000" | bc)
printf "Upload:%16s Mbps\n" $(echo "scale=2; $upload_bandwidth / 1000000" | bc)
printf "RTT:%19s ms\n" $avg_rtt
printf "Jitter:%16s ms\n" $jitter
printf "Packet loss:%11s %%\n" $packet_loss
