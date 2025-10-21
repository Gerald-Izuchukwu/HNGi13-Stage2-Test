FROM alpine:latest

EXPOSE 9600

CMD ["sh", "-c", "echo 'Hi from HNG13' && sleep infinity"]

