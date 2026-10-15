{{/*
Expand the name of the chart.
*/}}
{{- define "cortex-xdr.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cortex-xdr.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "cortex-xdr.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cortex-xdr.labels" -}}
helm.sh/chart: {{ include "cortex-xdr.chart" . }}
{{ include "cortex-xdr.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cortex-xdr.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cortex-xdr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Secret names
*/}}
{{- define "cortex-xdr.dockerPullSecretName" -}}
{{- if not .Values.dockerPullSecret.create }}
{{- .Values.dockerPullSecret.name }}
{{- else }}
{{- include "cortex-xdr.fullname" . }}-docker-pull-secret
{{- end }}
{{- end }}

{{- define "cortex-xdr.deploymentSecretName" -}}
{{- include "cortex-xdr.fullname" . }}-deployment
{{- end }}

{{- define "cortex-xdr.clusterRoleBindingName" -}}
{{- include "cortex-xdr.fullname" . }}-clusterrolebinding
{{- end }}

{{- define "cortex-xdr.clusterRoleName" -}}
{{- include "cortex-xdr.fullname" . }}-clusterrole
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cortex-xdr.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cortex-xdr.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate tsfPersistentStorage. Fails install/upgrade on a missing or unsafe configuration.
Numbers are checked as strings: an integer 0 counts as "empty" in Helm, so `if` would skip it.
*/}}
{{- define "cortex-xdr.validateTsfPersistentStorage" -}}
{{- with .Values.tsfPersistentStorage }}
{{- if .enabled }}
{{- if not .pvcName }}{{ fail "tsfPersistentStorage.enabled=true requires tsfPersistentStorage.pvcName" }}{{ end }}
{{- if not .path }}{{ fail "tsfPersistentStorage.enabled=true requires tsfPersistentStorage.path" }}{{ end }}
{{- if or (hasPrefix "/" (toString .path)) (has ".." (splitList "/" (toString .path))) }}{{ fail "tsfPersistentStorage.path must be relative and must not contain '..'" }}{{ end }}
{{- if not (regexMatch "^[A-Za-z0-9._/-]+$" (toString .path)) }}{{ fail "tsfPersistentStorage.path may contain only letters, digits, '.', '_', '-' and '/'" }}{{ end }}
{{- end }}
{{- range $name := list "memoryTsfTrigger" "cpuTsfTrigger" }}
{{- $t := get $.Values.tsfPersistentStorage $name | default dict }}
{{- if $t.enabled }}
{{- if not $.Values.tsfPersistentStorage.enabled }}{{ fail (printf "tsfPersistentStorage.%s.enabled=true requires tsfPersistentStorage.enabled=true" $name) }}{{ end }}
{{- if not (regexMatch "^([1-9][0-9]?|100)$" (toString $t.percent)) }}{{ fail (printf "tsfPersistentStorage.%s.percent must be an integer from 1 to 100" $name) }}{{ end }}
{{- if not (regexMatch "^[1-9][0-9]*$" (toString $t.seconds)) }}{{ fail (printf "tsfPersistentStorage.%s.seconds must be a positive integer" $name) }}{{ end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Env vars for one TSF resource trigger, rendered only when the trigger is enabled.
Args: list <root context> <values key> <env prefix>
*/}}
{{- define "cortex-xdr.tsfTriggerEnv" -}}
{{- $t := get (index . 0).Values.tsfPersistentStorage (index . 1) | default dict }}
{{- if $t.enabled }}
- name: {{ index . 2 }}_PERCENT
  value: {{ toString $t.percent | quote }}
- name: {{ index . 2 }}_SECONDS
  value: {{ toString $t.seconds | quote }}
{{- end }}
{{- end }}

{{/*
Create the path of the /var/log volume mount on the host fs
*/}}
{{- define "cortex-xdr.XdrVarLogHostPath" -}}
{{- if .Values.platform.bottlerocket -}}
/local/traps/var/log
{{- else -}}
/var/log
{{- end }}
{{- end }}

{{/*
Specify the SELinux context options type
*/}}
{{- define "cortex-xdr.xdrSelinuxOptionsType" -}}
{{- if .Values.platform.bottlerocket -}}
{{- print "super_t" -}}
{{- else if .Values.daemonset.selinuxOptionsSpcT -}}
{{- print "spc_t" -}}
{{- else -}}
{{- print "" -}}
{{- end -}}
{{- end -}}

{{/*
Effective agent flavor: 1 (standard) or 3 (cloud/sensor).
*/}}
{{- define "cortex-xdr.agentFlavor" -}}
{{- if hasKey .Values.agent "sensorMode" -}}
{{- fail "agent.sensorMode was removed in chart 1.11.0 - use agent.agentFlavor: 3 instead." -}}
{{- end -}}
{{- $raw := .Values.agent.agentFlavor -}}
{{- if kindIs "invalid" $raw -}}
{{- $raw = 1 -}}
{{- end -}}
{{- $agentFlavor := int $raw -}}
{{- if eq $agentFlavor 2 -}}
{{- fail "agent.agentFlavor=2 (nano) is not supported." -}}
{{- else if not (has $agentFlavor (list 1 3)) -}}
{{- fail (printf "agent.agentFlavor must be 1 (standard) or 3 (cloud/sensor), got '%v'" $raw) -}}
{{- end -}}
{{- $agentFlavor -}}
{{- end -}}

{{/*
Select the daemonset resources block based on agent.agentFlavor.
  agentFlavor: 3 -> .Values.daemonset.resources.sensor
  otherwise      -> .Values.daemonset.resources.full
*/}}
{{- define "cortex-xdr.daemonsetResources" -}}
{{- if eq (include "cortex-xdr.agentFlavor" .) "3" -}}
{{- toYaml .Values.daemonset.resources.sensor -}}
{{- else -}}
{{- toYaml .Values.daemonset.resources.full -}}
{{- end -}}
{{- end -}}
