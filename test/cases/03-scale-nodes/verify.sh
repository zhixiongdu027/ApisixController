#!/bin/bash

kubectl apply -f "${CASE_PATH}"/rules.yaml
sleep 3s

set -ex
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 200 ]]

kubectl scale -n test-apisix deployment test-service --replicas=0
sleep 3s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 503 ]]

kubectl scale -n test-apisix deployment test-service --replicas=2
sleep 10s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 200 ]]

kubectl scale -n test-apisix deployment test-service --replicas=0
sleep 3s
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 503 ]]

kubectl scale -n test-apisix deployment test-service --replicas=1
sleep 10s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 200 ]]
