FROM nginx:mainline-alpine3.17-slim

ADD https://github.com/openspeedtest/Speed-Test/archive/refs/heads/main.zip /tmp/
ADD --chmod=0755 https://raw.githubusercontent.com/brenozd/tc-easy/fixes/tc-easy.sh /bin/tc-easy

ENV CONFIG=/etc/nginx/conf.d/OpenSpeedTest-Server.conf

COPY /files/OpenSpeedTest-Server.conf ${CONFIG}
COPY /files/entrypoint.sh /entrypoint.sh
RUN rm /etc/nginx/nginx.conf
COPY /files/nginx.conf /etc/nginx/
COPY /files/nginx.crt /etc/ssl/
COPY /files/nginx.key /etc/ssl/

RUN	unzip -q /tmp/main.zip -d /usr/share/nginx/html/ \
	&& mv /usr/share/nginx/html/Speed-Test-main/* /usr/share/nginx/html/ \
	&& rm -rf /usr/share/nginx/html/Speed-Test-main/ \
	&& rm -rf /etc/nginx/conf.d/default.conf \
	&& chown -R nginx /usr/share/nginx/html/ \
	&& chmod 755 /usr/share/nginx/html/downloading \
	&& chmod 755 /usr/share/nginx/html/upload \
	&& chown nginx ${CONFIG} \
	&& chmod 400 ${CONFIG} \
	&& chown nginx /etc/nginx/nginx.conf \
	&& chmod 400 /etc/nginx/nginx.conf \
	&& chmod +x /entrypoint.sh

RUN apk add --no-cache ca-certificates iproute2-tc && update-ca-certificates

EXPOSE 3000 3001

STOPSIGNAL SIGQUIT

CMD ["/entrypoint.sh"]
