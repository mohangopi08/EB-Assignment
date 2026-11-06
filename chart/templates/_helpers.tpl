{{- define "demo.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "demo.labels" -}}
app.kubernetes.io/name: {{ include "demo.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "demo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
