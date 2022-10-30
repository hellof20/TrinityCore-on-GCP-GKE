FROM flant/shell-operator:latest
RUN apk --no-cache add curl
RUN apk --no-cache add mysql-client
RUN apk --no-cache add gettext libintl
ADD hooks /hooks
