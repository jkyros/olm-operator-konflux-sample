#!/usr/bin/env bash

# TODO(jkyros): Fish this out of the operator repo, maybe "most recent manifest version in keda/ or something" 
# TODO(jkyros): Somehow we need to add that to the FBC also and populate our CI_SPEC_RELEASE
export VERSION=$(ls custom-metrics-autoscaler-operator/keda/ | sort -rV | head -n1)
mv /custom-metrics-autoscaler-operator/keda/${VERSION}/manifests/ /manifests/
mv /custom-metrics-autoscaler-operator/keda/${VERSION}/metadata/ /metadata/


export CI_SPEC_RELEASE="454"

# TODO(jkyros): So here's how this works -- we put these variables in here, and then Konflux comes through and updates them when the builds get updated, ideally
# not causing cyclical builds, so we have to exclude this somehow I think 
export CMA_OPERATOR_PULLSPEC=quay.io/repository/redhat-user-workloads/cma-podauto-tenant/custom-metrics-autoscaler-operator@sha256:4632bc387e54960ce0bb0fdb4fdda89dbc8c7afc16c2427ff6e517fb47379256
export KEDA_OPERATOR_PULLSPEC=quay.io/repository/redhat-user-workloads/cma-podauto-tenant/keda-operator@sha256:4632bc387e54960ce0bb0fdb4fdda89dbc8c7afc16c2427ff6e517fb47379256
export KEDA_ADAPTER_PULLSPEC=quay.io/repository/redhat-user-workloads/cma-podauto-tenant/keda-adapter@sha256:4632bc387e54960ce0bb0fdb4fdda89dbc8c7afc16c2427ff6e517fb47379256
export KEDA_WEBHOOK_PULLSPEC=quay.io/repository/redhat-user-workloads/cma-podauto-tenant/keda-webhooks@sha256:4632bc387e54960ce0bb0fdb4fdda89dbc8c7afc16c2427ff6e517fb47379256

# Since we moved the versioned manifest to /manifests, we can just use it from there
export CSV_FILE=/manifests/cma.v${VERSION}.clusterserviceversion.yaml

# Update image references to use brew-built images
# Put the allowed repositories: OSBS proxy and registry.redhat.io.
# The pinning to SHA1 will happen after thanks to the config in container.yaml.
# TODO(jkyros): I think the FBC will take care of the replaces, etc based on the catalog so we don't have to do it 
sed -i -e "s#ghcr.io/kedacore/keda-olm-operator:\(main\|[0-9.]*\)#${CMA_OPERATOR_PULLSPEC}#g" \
       -e "s#CMA_OPERAND_PLACEHOLDER_1\$#${KEDA_OPERATOR_PULLSPEC}#g" \
       -e "s#CMA_OPERAND_PLACEHOLDER_2\$#${KEDA_ADAPTER_PULLSPEC}#g" \
       -e "s#CMA_OPERAND_PLACEHOLDER_3\$#${KEDA_WEBHOOK_PULLSPEC}#g" \
       -e "s/^\(  *\)olm.skipRange: '>=2.7.1 <[0-9.-]*'/\1olm.skipRange: '>=2.7.1 <${VERSION}-${CI_SPEC_RELEASE}'/" \
       -e '/^metadata:$/,/^spec:$/ s/^\(  name: custom-metrics-autoscaler\.v\)[0-9.]*$/\1'"${VERSION}-${CI_SPEC_RELEASE}"'/' \
       -e '/^spec:$/,$ s/^\(  version: \)[0-9.]*$/\1'"${VERSION}-${CI_SPEC_RELEASE}"'/' \
       "${CSV_FILE}"
cat "${CSV_FILE}"


export AMD64_BUILT=$(skopeo inspect --raw docker://${GATEKEEPER_OPERATOR_IMAGE_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="amd64")')
export ARM64_BUILT=$(skopeo inspect --raw docker://${GATEKEEPER_OPERATOR_IMAGE_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="arm64")')
export PPC64LE_BUILT=$(skopeo inspect --raw docker://${GATEKEEPER_OPERATOR_IMAGE_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="ppc64le")')
export S390X_BUILT=$(skopeo inspect --raw docker://${GATEKEEPER_OPERATOR_IMAGE_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="s390x")')

export EPOC_TIMESTAMP=$(date +%s)
# time for some direct modifications to the csv
python3 - << CSV_UPDATE
import os
from collections import OrderedDict
from sys import exit as sys_exit
from datetime import datetime
from ruamel.yaml import YAML
yaml = YAML()
def load_manifest(pathn):
   if not pathn.endswith(".yaml"):
      return None
   try:
      with open(pathn, "r") as f:
         return yaml.load(f)
   except FileNotFoundError:
      print("File can not found")
      exit(2)

def dump_manifest(pathn, manifest):
   with open(pathn, "w") as f:
      yaml.dump(manifest, f)
   return
timestamp = int(os.getenv('EPOC_TIMESTAMP'))
datetime_time = datetime.fromtimestamp(timestamp)
gatekeeper_csv = load_manifest(os.getenv('CSV_FILE'))
# Add arch support labels
gatekeeper_csv['metadata']['labels'] = gatekeeper_csv['metadata'].get('labels', {})
if os.getenv('AMD64_BUILT'):
	gatekeeper_csv['metadata']['labels']['operatorframework.io/arch.amd64'] = 'supported'
if os.getenv('ARM64_BUILT'):
	gatekeeper_csv['metadata']['labels']['operatorframework.io/arch.arm64'] = 'supported'
if os.getenv('PPC64LE_BUILT'):
	gatekeeper_csv['metadata']['labels']['operatorframework.io/arch.ppc64le'] = 'supported'
if os.getenv('S390X_BUILT'):
	gatekeeper_csv['metadata']['labels']['operatorframework.io/arch.s390x'] = 'supported'
gatekeeper_csv['metadata']['labels']['operatorframework.io/os.linux'] = 'supported'
gatekeeper_csv['metadata']['annotations']['createdAt'] = datetime_time.strftime('%d %b %Y, %H:%M')
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/disconnected'] = 'true'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/fips-compliant'] = 'true'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/proxy-aware'] = 'false'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/tls-profiles'] = 'false'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-aws'] = 'false'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-azure'] = 'false'
gatekeeper_csv['metadata']['annotations']['features.operators.openshift.io/token-auth-gcp'] = 'false'
gatekeeper_csv['metadata']['annotations']['repository'] = 'https://github.com/openshift/custom-metrics-autoscaler-operator'
gatekeeper_csv['metadata']['annotations']['containerImage'] = os.getenv('CMA_OPERATOR_PULLSPEC', '')

dump_manifest(os.getenv('CSV_FILE'), gatekeeper_csv)
CSV_UPDATE

cat $CSV_FILE

