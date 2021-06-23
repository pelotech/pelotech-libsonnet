local version = "v0.48.1";
local kube = import 'https://github.com/bitnami-labs/kube-libsonnet/raw/v1.14.6/kube.libsonnet';
local prometheus_operator = import 'https://github.com/prometheus-operator/prometheus-operator/raw/v0.48.1/jsonnet/prometheus-operator/prometheus-operator.libsonnet';

{
    local this = self,
    namespace_:: 'monitoring',
    create_namespace:: true,

    namespace: if this.create_namespace then kube.Namespace(this.namespace_) else null,

    operator: prometheus_operator({
        version: version,
        namespace: this.namespace_,
        image: 'quay.io/prometheus-operator/prometheus-operator:%s' % version,
        configReloaderImage: 'quay.io/prometheus-operator/prometheus-config-reloader:%s' % version
    })
}