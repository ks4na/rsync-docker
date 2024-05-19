FROM alpine

RUN apk add --update-cache \
    rsync \
    openssh-client \
    tzdata \
    msmtp \
 && rm -rf /var/cache/apk/*

COPY rsync.sh sync_and_email.sh ./

ENTRYPOINT [ "./rsync.sh" ]
