#!/bin/bash

SCRIPT_DIR="$(dirname "$BASH_SOURCE")"

TEST_NAME_SPACE=test-apisix
TEST_HTTP_PORT=39080
TEST_HTTPS_PORT=39443

APISIX_CONTROLLER_IP=$(kubectl get nodes -o wide | grep minikube | awk '{print $6}')
export APISIX_CONTROLLER_HTTP_ADDRESS=${APISIX_CONTROLLER_IP}:${TEST_HTTP_PORT}
export APISIX_CONTROLLER_HTTPS_ADDRESS=${APISIX_CONTROLLER_IP}:${TEST_HTTPS_PORT}

TEST_SERVIER_YAML="$(dirname "$BASH_SOURCE")/test-service.yaml"
kubectl apply -f ${TEST_SERVIER_YAML}
CASES_DIR="$(dirname "$BASH_SOURCE")/cases"
TEST_RUNNER="$(dirname "$BASH_SOURCE")/run-one-test.sh"

let TESTS_PASSED=0 TESTS_FAILED=0
for CASE_PATH in "$CASES_DIR"/*; do
  CASE_NAME="$(basename "$CASE_PATH")"

  if env \
    CASE_NAME="$CASE_NAME" \
    CASE_PATH="$CASE_PATH" \
    $TEST_RUNNER; then
    let TESTS_PASSED++
  else
    echo ">>> Test $CASE_NAME exited with status $?"
    let TESTS_FAILED++
  fi
done

kubectl delete -f ${TEST_SERVIER_YAML}
echo ">>> Overall tests PASSED: $TESTS_PASSED"
echo ">>> Overall tests FAILED: $TESTS_FAILED"

[[ $TESTS_FAILED == 0 ]]
