FROM alpine:3.23

RUN apk update && apk add --no-cache nginx openssl

RUN mkdir -p /etc/nginx/ssl \
    && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout /etc/nginx/ssl/tfournie.key \
       -out    /etc/nginx/ssl/tfournie.crt \
       -subj "/C=FR/L=Lyon/O=42/CN=tfournie.42.fr"

COPY conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443
ENTRYPOINT ["nginx", "-g", "daemon off;"]