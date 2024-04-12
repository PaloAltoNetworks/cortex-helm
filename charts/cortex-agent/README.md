# Cortex XDR Helm Chart

## Chart versions

| Chart version | Agent version | Notes
|---------------|---------------|--------------------------------------------------
| 1.0.0         | >=7.5         |
| 1.1.0         | >=7.5         |
| 1.2.0         | >=7.5         |
| 1.3.0         | >=7.5         |
| 1.4.0         | >=7.5         | Support for endpointTags from agent 8.1
| 1.5.0         | >=7.5         | Support for optional cluster name from agent 8.2
| 1.6.0         | >=7.5         |
| 1.6.1         | >=7.5         | Namespace is created by the chart and no longer by helm itself. Therefore the helm namespace will be `default` (unless chosen otherwise).
| 1.6.2         | >=7.5         |
| 1.7.0         | >=7.5         | Bottlerocket support
| 1.8.0         | >=7.5         | SELinux spc_t (Super Privileged Container) support

## Installing Cortex XDR helm chart

### Add the Cortex XDR helm repository
```
helm repo add paloaltonetworks https://paloaltonetworks.github.io/cortex-helm
```

### Verify that the repository was added to helm repo cache
```
helm repo list | grep paloaltonetworks
```

### List all available charts in the repo
```
helm search repo --versions paloaltonetworks
```

* Parameters **required** for the chart installation (not for upgrade):
    - docker config json value or name of the secret that contains the value.
    - image repository url.
    - distribution id.

**Below examples are also retrievable from the private cortex tenant with all the above parameters already supplied.**

#### Notes

- If no namespace is set in the installation command, the namespace will be `cortex-xdr`.
- Namespace can be whatever you'd like (`cortex-xdr` is not mandatory).

**Notice image tag is also the agent version**

Classic installation command:
```
helm upgrade --install <release_name> <helm_chart> \
  --set daemonset.image.repository=<repository_url> \
  --set daemonset.image.tag=<agent_version_tag> \
  --set agent.distributionId=<distribution_id> \
  --set dockerPullSecret.create=true \
  --set dockerPullSecret.value=<docker_config_json_secret>
```

Note: to pick a specific version, use the `--version` flag.

If the secret was created seperately then you can just supply the secret name (make sure the secret and the agent are in the same namespace):
```
helm upgrade --install <release_name> <helm chart> \
  --set daemonset.image.repository=<repository_url> \
  --set daemonset.image.tag=<agent_version> \
  --set agent.distributionId=<distribution_id> \
  --set dockerPullSecret.name=<docker_config_json_secret>
```

Upgrade example:
```
helm repo update
```

```
helm upgrade --install <release_name> <helm_chart> --reuse-values \
  --namespace=<namespace> \
  --set daemonset.image.tag=<new_agent_version_tag>
```

Even when using `--reuse-values` (which uses the values of the previous installation) you can still override any value that you want with the `--set` option.

### More installation Parameters
|Parameter                               | Description                                                                                                | Notes
|----------------------------------------|------------------------------------------------------------------------------------------------------------|-------------
| `daemonset.image.repository`           | Cortex image Repository URL (Required)                                                                     |
| `dockerPullSecret.create`              | Create/Don't create docker config json pull secret and insert the value in it                              |
| `dockerPullSecret.value`               | Docker config json value for the docker pull secret (Required)                                             |
| `dockerPullSecret.name`                | Docker config json secret name (Required if value isn't supplied)                                          |
| `agent.distributionId`                 | Distribution id of the tenant (Required)                                                                   |
| `agent.distributionServer`             | Distribution server URL (set by default in the image)                                                      |
| `agent.proxyList`                      | List of proxies that the agent will use (e.g `--set agent.proxyList="10.0.0.1:8000\,10.0.0.2:9000"`)       |
| `agent.endpointTags`                   | List of tags describing the endpoint (e.g `--set agent.endpointTags="main\,dev-machine1\,test\ 123"`)      | Since 1.4.0
| `agent.nodeSelector`                   | Node selector (e.g `--set daemonset.nodeSelector.<key=value>`, each key+value will need their own `--set`) |
| `serviceAccount.openshift.scc.create`  | Enable `SecurityConstraintsContext` for openshift platform (Required when installing on openshift)         |
| `platform.talos`                       | Support for TalOS platform (Required when installing on TalOS)                                             | Since 1.5.0, agent >= 8.2
| `platform.gcos`                        | Support for GCOS (Google Container-Optimized OS) platform (Required when installing on GCOS)               | Since 1.5.0, agent >= 8.2
| `platform.bottlerocket`                | Support for BottlerocketOS platform (Required when installing on BottlerocketOS)                           | Since 1.6.3, agent >= 8.3
| `agent.clusterName`                    | Name of the kuberenets cluster, will be used as part of the information sent to the server                 | Since 1.5.0, agent >= 8.2
| `namespace.name`                       | Name of the namespace the agent resides on                                                                 | Since 1.6.0
| `namespace.create`                     | Create/Don't create namespace for the agent                                                                | Since 1.6.0
| `daemonset.selinuxOptionsSpcT`         | Set SELinux Options type to 'spc_t'                                                                        | Since 1.8.0

Note: Helm requires commas in arguments to be escaped.

## Uninstalling Cortex XDR helm chart

```
helm uninstall <release_name>
```
