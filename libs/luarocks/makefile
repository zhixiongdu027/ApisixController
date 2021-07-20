
LUAROCKS_TREE="/root/usr/local/apisix/deps"
SUBDIRS=$(shell ls -l | grep ^d | awk '{print $$9}')

.PHONY :all prepare subdirs
all: prepare subdirs
prepare:
	yum makecache && yum install lua-devel wget unzip gcc -y
	wget https://luarocks.org/releases/luarocks-3.3.1.tar.gz
	tar zxpf luarocks-3.3.1.tar.gz
	cd luarocks-3.3.1 && ./configure --with-lua-include=/usr/include && make && make install
	mkdir -p ${LUAROCKS_TREE}

subdirs:$(SUBDIRS) $(CUR_OBJS)
$(SUBDIRS):ECHO
	make -C $@
ECHO:
	@echo $(SUBDIRS)
