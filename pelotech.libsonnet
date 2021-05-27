local kube = import 'kube.libsonnet';

{
    nodejs_application(name):: {
        labels:: {},
        app_config:: {},

        configmap: if self._configuration != {} then kube.ConfigMap('%s-config' % name) {
            metadata+: {
                labels+: self.labels
            },
            data: { configuration: std.manifestJsonEx(self._configuration, '  ') },
        } else null,

        deployment: kube.Deployment(name),
    },
}