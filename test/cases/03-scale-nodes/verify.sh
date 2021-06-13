#!/bin/bash
set -ex
# we had not set any route rule ,so any request should be response 404 code
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/xxx)" == 200 ]

kubectl scale -n test-apisix deployment test-service --replicas=0
sleep 2s

[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal)" == 503 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/)" == 503 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/xxx)" == 503 ]

kubectl scale -n test-apisix deployment test-service --replicas=2
sleep 10s

[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/xxx)" == 200 ]

kubectl scale -n test-apisix deployment test-service --replicas=0
sleep 2s
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal)" == 503 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/)" == 503 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/xxx)" == 503 ]


kubectl scale -n test-apisix deployment test-service --replicas=1
sleep 10s

[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/)" == 200 ]
[ "$(curl -sw '%{http_code}' -o /dev/null http://$APISIX_CONTROLLER_HTTP_ADDRESS/normal/xxx)" == 200 ]