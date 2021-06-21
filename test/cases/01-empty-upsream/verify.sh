#!/bin/bash
set -ex

kubectl apply -f "${CASE_PATH}"/rules_without_label.yaml
sleep 3s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream/)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream/xxx)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstreamxxx)" == 404 ]]

kubectl apply -f "${CASE_PATH}"/rules_with_label.yaml
sleep 3s
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream)" == 500 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream/)" == 500 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstream/xxx)" == 500 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/emptyupstreamxxx)" == 404 ]]
