#!/bin/bash
set -ex
# we had not set any route rule ,so any request should be response 404 code
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/emptyupstream)" == 500 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/emptyupstream/)" == 500 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/emptyupstream/xxx)" == 500 ]