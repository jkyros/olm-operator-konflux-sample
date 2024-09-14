#!/usr/bin/env bash

# TODO(jkyros): Fish this out of the operator repo, maybe "most recent manifest version in keda/ or something" 
# TODO(jkyros): Somehow we need to add that to the FBC also and populate our CI_SPEC_RELEASE
export VERSION=$(ls custom-metrics-autoscaler-operator/keda/ | sort -rV | head -n1)
mv /custom-metrics-autoscaler-operator/keda/${VERSION}/manifests/ /manifests/
mv /custom-metrics-autoscaler-operator/keda/${VERSION}/metadata/ /metadata/


export CI_SPEC_RELEASE="454"

# TODO(jkyros): So here's how this works -- we put these variables in here, and then Konflux comes through and updates them when the builds get updated, ideally
# not causing cyclical builds, so we have to exclude this somehow I think 
export CMA_OPERATOR_PULLSPEC=quay.io/redhat-user-workloads/cma-podauto-tenant/custom-metrics-autoscaler-operator/custom-metrics-autoscaler-operator@sha256:a230a6f5c6aa6bbbbad0175e68f44016933982e00f5f19422e5e8db67b7d4e6d
export KEDA_OPERATOR_PULLSPEC=quay.io/redhat-user-workloads/cma-podauto-tenant/custom-metrics-autoscaler-operator/keda-operator@sha256:b2080eeba74d6e1a13dafb6b35c1c765384610382798910e33b102a7f09fb913
export KEDA_WEBHOOK_PULLSPEC=quay.io/redhat-user-workloads/cma-podauto-tenant/custom-metrics-autoscaler-operator/keda-webhooks@sha256:81c9bff7a41a7c74bc233d0a6ce19cb4d6cc113821369a26748ebb1d9bb9e847
export KEDA_ADAPTER_PULLSPEC=quay.io/redhat-user-workloads/cma-podauto-tenant/custom-metrics-autoscaler-operator/keda-adapter@sha256:b5b63a976d7e1cacf201cc0d75ab63d43cf7141f874cc447cb29fcfba2b392fe

# Since we moved the versioned manifest to /manifests, we can just use it from there
export CSV_FILE=/manifests/cma.v${VERSION}.clusterserviceversion.yaml


# CPaaS used to do this for us, but now we have to do it ourselves 
cat << EOF >> ${CSV_FILE}
  relatedImages: 
    - name: keda-operator
      image: ${KEDA_OPERATOR_PULLSPEC}
    - name: keda-adapter
      image: ${KEDA_ADAPTER_PULLSPEC}
    - name: keda-webhooks
      image: ${KEDA_WEBHOOK_PULLSPEC}
    - name: cma-operator
      image: ${CMA_OPERATOR_PULLSPEC}
EOF

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


# TODO(jkyros): check all the images probably so we don't have an odd one out that's missing on a platform, e.g. CMA 
# built for arm, but the webhook only built for x86_64, etc. 
export AMD64_BUILT=$(skopeo inspect --raw docker://${CMA_OPERATOR_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="amd64")')
export ARM64_BUILT=$(skopeo inspect --raw docker://${CMA_OPERATOR_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="arm64")')
export PPC64LE_BUILT=$(skopeo inspect --raw docker://${CMA_OPERATOR_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="ppc64le")')
export S390X_BUILT=$(skopeo inspect --raw docker://${CMA_OPERATOR_PULLSPEC} | jq -e '.manifests[] | select(.platform.architecture=="s390x")')

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

