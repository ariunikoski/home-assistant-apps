FROM ghcr.io/home-assistant/base:latest

RUN apk add --no-cache bashio

COPY run.sh /

RUN chmod a+x /run.sh

CMD ["/run.sh"]
