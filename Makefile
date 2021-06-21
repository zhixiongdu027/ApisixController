
ifeq (${hub}, )
  $(error you should set hub value like "make all hub=[docker hub address]")
endif

ifeq (${version}, )
  ImageTag = ${hub}/apisix-controller
else
  ImageTag = ${hub}/apisix-controller:${version}
endif

.PHONY: install
install:
	@docker build -t ${ImageTag} .
	@docker push ${ImageTag}
	@helm install apisix-controller --set image=${ImageTag} ./helm

.PHONY: test
test:
	@minikube start
	@docker build -t ${ImageTag} .
	@docker push ${ImageTag}
	-helm delete test-apisix-controller -n test-apisix
	@helm install test-apisix-controller -n test-apisix --create-namespace                           \
		--set exposeMode=HostPort --set httpPort=3980 --set httpsPort=39443 --set image=${ImageTag}  \
		./helm
	@sleep 1m
	@chmod +x test/test.sh
	@test/test.sh
	-helm delete test-apisix-controller -n test-apisix