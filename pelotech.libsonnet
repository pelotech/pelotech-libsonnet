local kube = import 'kube.libsonnet';

{

    EmptyDirVolume():: kube.EmptyDirVolume(),
    HostPathVolume(path, type=''):: kube.HostPathVolume(path, type),
    GitRepoVolume(repository, revision):: kube.GitRepoVolume(repository, revision),
    SecretVolume(secret):: kube.SecretVolume(secret),
    ConfigMapVolume(configmap):: kube.ConfigMapVolume(configmap),

    generic_application(name):: {
        local this = self,

        config:: {
            extraLabels: {},
            replicaCount: 1,
            image: {
                registry: error 'image registry must be provided',
                repository: error 'image repository must be provided',
                tag: 'latest',
                pullPolicy: if this.config.image.tag == 'latest' then 'Always' else 'IfNotPresent',
            },
            service: {
                annotations: {},
                type: 'ClusterIP',
                port: 8080,
            },
            healthCheck: '/healthz',
            environment: {},
            resources: {},
            nodeSelector: {},
            tolerations: [],
            affinity: {},
            podAnnotations: {},
            volumes: {},
            volumeMounts: {},
        },

        deployment: kube.Deployment(name) {
            metadata+: {
                labels+: if this.config.extraLabels != {} then this.config.extraLabels else {},
            },
            spec+: {
                replicas: this.config.replicaCount,
                template+: {
                    metadata+: {
                        annotations+: this.config.podAnnotations,
                    },
                    spec+: {
                        containers_+: {
                            app: kube.Container(name) {
                                image: '%s/%s:%s' % [this.config.image.registry, this.config.image.repository, this.config.image.tag],
                                resources: this.config.resources,
                                env_+: this.config.environment,
                                ports_+: { http: { containerPort: this.config.service.port} },
                                livenessProbe: {
                                    httpGet: {
                                        path: this.config.healthCheck,
                                        port: 'http',
                                    },
                                },
                                readinessProbe: {
                                    httpGet: {
                                        path: this.config.healthCheck,
                                        port: 'http',
                                    },
                                },
                                volumeMounts_+: this.config.volumeMounts,
                            },
                        },
                        volumes_+: this.config.volumes,
                    },
                },
            },
        },
    },

    nodejs_application(name):: $.generic_application(name) {
        local this = self,

        config+:: {
            image+: {
                registry: 'docker.io',
                repository: 'node'
            },
            service+: {
                port: 81,
            },
            appConfig: {},
            appDirectory: '/usr/src/app',
            volumeMounts+: if this.configmap == null then {} else {
                config: { 
                    mountPath: '%s/config/production.json' % this.config.appDirectory,
                    subPath: 'configuration',
                }
            },
            volumes+: if this.configmap == null then {} else {
                config: $.ConfigMapVolume(this.configmap)
            },
        },

        configmap: if this.config.appConfig != {} then kube.ConfigMap('%s-config' % name) {
            metadata+: {
                labels+: if this.config.extraLabels != {} then this.config.extraLabels else {},
            },
            data: { configuration: std.manifestJsonEx(this.config.appConfig, '  ') },
        } else null,
    },
}