#!/bin/bash

set -ex

[[ "$(kubectl apply -f "${CASE_PATH}"/not_exist_rules.yaml 2>&1)" =~ "denied the request:" ]]

[[ "$(kubectl apply -f "${CASE_PATH}"/vaild_failed.yaml 2>&1)" =~ "denied the request:" ]]

[[ "$(kubectl apply -f "${CASE_PATH}"/proxy-rewrite-first.yaml)" =~ "created" ]]
sleep 3s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/firstxxx)" == 404 ]]

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second/xxx)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/secondxxx)" == 404 ]]

[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first)" == "/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first/)" == "/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first/xxx)" == "/xxx" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first/xxx/abc)" == "/xxx/abc" ]]

[[ "$(kubectl apply -f "${CASE_PATH}"/proxy-rewrite-second.yaml)" == "rule.apisix.apache.org/test-route configured" ]]
sleep 3s

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/first/xxx)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/firstxxx)" == 404 ]]

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second/xxx)" == 200 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/secondxxx)" == 404 ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second)" == "/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second/)" == "/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second/xxx)" == "/xxx" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/second/xxx/abc)" == "/xxx/abc" ]]

kubectl apply -f "${CASE_PATH}"/proxy-echo.yaml
sleep 3s
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal)" == "append by echo/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/)" == "append by echo/" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx)" == "append by echo/xxx" ]]
[[ "$(curl http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/normal/xxx/abc)" == "append by echo/xxx/abc" ]]
