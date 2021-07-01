LUAROCKS_TREE="/root/usr/local/apisix/deps"

.PHONY: lyaml
lyaml:
	yum install libyaml-devel -y
	luarocks install lyaml --tree=${LUAROCKS_TREE}
	mkdir -p /root/usr/lib64
	ls /usr/lib64 -a |grep libyaml |xargs -I {} cp -P /usr/lib64/{} /root/usr/lib64