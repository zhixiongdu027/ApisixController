#!/bin/bash

set -ex

[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}")" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/foo)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/foo/)" == 404 ]]
[[ "$(curl -sw '%{http_code}' -o /dev/null http://"${APISIX_CONTROLLER_HTTP_ADDRESS}"/foo/xxx)" == 404 ]]
