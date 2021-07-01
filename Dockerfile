FROM apache/apisix:2.7-centos As First
RUN  mkdir -p /root/usr/local/apisix
COPY apisix /root/usr/local/apisix
COPY patch /root
RUN yum makecache && yum install make -y
COPY libs /tmp/libs
RUN  cd /tmp/libs && make all

FROM apache/apisix:2.7-centos
COPY --from=First /root/ /