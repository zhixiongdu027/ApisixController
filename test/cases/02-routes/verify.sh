#!/bin/bash

kubectl apply -f "${CASE_PATH}"/rules.yaml
sleep 3s

set -ex
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"$APISIX_CONTROLLER_HTTP_ADDRESS"/normal)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"$APISIX_CONTROLLER_HTTP_ADDRESS"/normal/)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normalxxx)" == 200 ]]

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/nonexistent)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/nonexistent/)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/nonexistent/xxx)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/nonexistentxxx)" == 503 ]]

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/noport)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/noport/)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/noport/xxx)" == 503 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/noportxxx)" == 503 ]]
