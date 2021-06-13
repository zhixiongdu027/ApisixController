FROM apache/apisix:2.6-centos As First
RUN  yum makecache
RUN  yum install gcc make lua-devel libyaml-devel wget unzip libyaml -y
RUN  wget https://luarocks.org/releases/luarocks-3.3.1.tar.gz
RUN  tar zxpf luarocks-3.3.1.tar.gz
RUN  mkdir -p /root/usr/lib64 && mkdir -p /root/usr/local/apisix/deps
RUN  cd luarocks-3.3.1 && ./configure --with-lua-include=/usr/include && make && make install
RUN  luarocks install lyaml --tree=/root/usr/local/apisix/deps --local
COPY apisix /root/usr/local/apisix
RUN  ls /usr/lib64 -a |grep libyaml |xargs -I {} cp -P /usr/lib64/{} /root/usr/lib64

FROM apache/apisix:2.6-centos
COPY --from=First /root /