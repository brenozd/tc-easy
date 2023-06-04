FROM alpine:3.18
RUN apk add --no-cache iperf3 iproute2-tc
ADD --chmod=0755 https://raw.githubusercontent.com/brenozd/tc-easy/fixes/tc-easy.sh /bin/tc-easy

ENTRYPOINT ["iperf3"]
CMD ["-s"]
EXPOSE 5201
EXPOSE 5201/udp