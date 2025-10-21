FROM alpine:latest
RUN apk add --no-cache busybox-extras
COPY index.html /index.html
EXPOSE 9600
CMD ["sh", "-c", "httpd -f -p 9600 -h /"]
