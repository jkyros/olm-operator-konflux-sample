# Onboarding process for Konflux

In order to increase transparency into the process of onboarding, we will document the steps taken in order to enable better reproducibility.

## Prepare the git repository (optional)

If you already have a git repository created for an artifact you want to build in Konflux then you can skip this step. It is likely that this will not be the desired pattern for many projects being onboarded as the intention behind Konflux is to shift testing as far left as possible (into the project repository itself, for example). Therefore, you will likely be onboarding a repository which is currently configured for building in another system.

In this repository, we used git submodules to [pull together multiple remote references](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/1) in order to specify the build configuration in one place. You should get the code in place which builds properly locally so that the onboarding process to Konflux can be simplified.

## Onboard component(s) to Konflux

After you have your git repository, the first step that is required is to create an application and onboard your component(s). This process can be done in either the UI or using a GitOps approach. While the initial component onboarding was performed using the UI for this sample, the CRs have also been defined via [GitOps after the fact](https://github.com/redhat-appstudio/tenants-config/pull/482).

### Merge tekton pipleine definitions

Regardless of how components are onboarded, each will have their own PR for creating the PipelinesAsCode (PAC) PipelineRuns to build the artifacts. In this sample, two components were initially onboarded, [gatekeeper](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/2) and [gatekeeper-operator](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/3). The PAC definitions for gatekeeper were merged even though they were failing as a follow-up PR was planned to overhaul the PipelineDefinitions.

After onboarding the components to Konflux, a PR will be sent to the repository with the pipeline definitions. The PR can be easily merged if the build completes as specified (i.e. with the provided context and Containerfile). If the repository or the Tekton PipelineRun need to be updated to get the build to pass, you can push changes to the source branch in the repository to update the PR.

### Customize tekton pipleines

After merging the initial Tekton PipelineRuns to the repository, the structure of the `.tekton` directory [was overhauled](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/4) to make it simpler to work on the components. Some of the key changes that were made include:

* Utilization of multi-arch builds. We knew that we would need to build the container images for multiple architectures, so this pipeline was added to the repository (in the future, it will be possible to directly onboard with a multi-arch pipeline).
* Use of common in-repo Tekton PipelineDefinitions for multi-arch and single-arch builds. The PAC PipelineRuns then refer to these PipelineDefinitions. This enables the pipeline to be modified once in the repository and then all components building with that definition will be updated for pull request and push events.
* Adding appropriate `on-cel-expression`s to reduce unnecessary builds while still rebuilding if any relevant content was modified.
* Utilization of OCI [trusted artifacts](https://konflux-ci.dev/architecture/ADR/0036-trusted-artifacts.html) to remove the dependency on a PersistentVolumeClaim for the pipeline.

More information on the specifics for these customizations can be found in [functionality-demonstrated.md](functionality-demonstrated.md).

NOTE: The multi-arch builds were not properly building the index image until [all architectures](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/15) were enabled.

### Add more Components as necessary

We onboarded the bundle component after the first two components were built. The process of onboarding components as well as merging and customizing the pipelines can be repeated until all components are created and building properly.

If all of your components are not building properly when you onboard new components, you may see some failures in the onboarding PR. For example, we saw a failure in the [onboarding PR](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/5) due to another component being built. That issue was being worked on in [another PR in parallel](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/4) and had not yet been merged. Another case where the PRs can indicate failure from other components is if the IntegrationTestScenarios (ITS) are reporting an error. Since the ITS is run against a snapshot of all components in an application, a failure in one (for example an enterprise contract violation) will report back on a PR for any component in the application. If you do not want to override the CI failures to merge, then you will need to ensure that the base reference is properly building before onboarding a new component.

When adding the bundle image, you will need to establish a process for maintianing the ClusterServiceVersion. This includes ensuring that `spec.relatedImages` is complete with all sha digest references for all images that may be required to install the operator which enables the images to be mirrored for a disconnected installation of the operator. You can either do this manually, with your own script, or with a tool like [operator-manifest](https://github.com/containerbuildsystem/operator-manifest#pull-specifications).

## Maintain the pipeline task references

Konflux leverages [Enterprise Contract](https://enterprisecontract.dev/) for verifying that artifacts comply with a specific set of policies. One of the policies that can be configured ensures that the task bundle reference is the [latest version available](https://enterprisecontract.dev/docs/ec-policies/release_policy.html#attestation_task_bundle__task_ref_bundles_current). In order to ensure that this policy does not fail, task updates proposed by Konflux need to be merged within 30 days. This task data is contained in the [data-acceptable-bundles](quay.io/konflux-ci/tekton-catalog/data-acceptable-bundles:latest) OCI artifact.

## Add component nudge relationships

In order to ensure that the bundle image is always up to date with the latest gatekeeper and gatekeeper-operator images, we need to configure [component nudges](https://konflux-ci.dev/docs/how-tos/configuring/component-nudges/). First, the Components were modified [via ArgoCD](https://github.com/redhat-appstudio/tenants-config/pull/498) and then we had to configure the push pipelines to indicate which files need to have the pullspecs updated in.

We prepared for these nudges by reworking how the bundles [are built](https://github.com/konflux-ci/olm-operator-konflux-sample/pull/16). In that PR, we ensured that we have the full pullspec (and digest) of the nudging components' images in a file. This process enables us to easily modify and update the ClusterServiceVersion in the bundle image. While it is possible to update the image pullspecs directly in the bundle as well, it was separated out here to specifically enable additional customizations on top of the `operator-sdk` tooling to build the bundle.