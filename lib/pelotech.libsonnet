local kube = import 'kube.libsonnet';

{

    application(name):: {
        local this = self,

        values:: {
            namespace: 'default',
            extraLabels: {},
            replicaCount: 1,
            image: {
                registry: 'docker.io',
                repository: error 'image repository must be provided',
                tag: 'latest',
                pullPolicy: if this.values.image.tag == 'latest' then 'Always' else 'IfNotPresent',
            },
            service: {
                enabled: false,
                annotations: {},
                type: 'ClusterIP',
                port: 8080,
            },
            healthCheck: '/healthz',
            environment: {},
            environmentFrom: [],
            resources: {},
            nodeSelector: {},
            tolerations: [],
            affinity: {},
            podAnnotations: {},
            volumes: {},
            volumeMounts: {},
            lifecycle: {},
        },

        deployment: kube.Deployment(name) {
            metadata+: {
                namespace: this.values.namespace,
                labels+: if this.values.extraLabels != {} then this.values.extraLabels else {},
            },
            spec+: {
                replicas: this.values.replicaCount,
                minReadySeconds: 10,
                template+: {
                    metadata+: {
                        annotations+: this.values.podAnnotations,
                    },
                    spec+: {
                        terminationGracePeriodSeconds: 10,
                        containers_+: {
                            app: kube.Container(name) {
                                image: '%s/%s:%s' % [this.values.image.registry, this.values.image.repository, this.values.image.tag],
                                resources: this.values.resources,
                                env_+: this.values.environment,
                                envFrom+: this.values.environmentFrom,
                                ports_+: if this.values.service.enabled then { http: { containerPort: this.values.service.port} } else {},
                                livenessProbe: if this.values.healthCheck != '' then {
                                    httpGet: {
                                        path: this.values.healthCheck,
                                        port: 'http',
                                    },
                                } else null,
                                readinessProbe: if this.values.healthCheck != '' then {
                                    httpGet: {
                                        path: this.values.healthCheck,
                                        port: 'http',
                                    },
                                } else null,
                                volumeMounts_+: this.values.volumeMounts,
                                lifecycle: this.values.lifecycle,
                            },
                        },
                        volumes_+: this.values.volumes,
                    },
                },
            },
        },

        service: if this.values.service.enabled then kube.Service(name) {
            target_pod: this.deployment.spec.template,
            metadata+: {
                namespace: this.values.namespace,
            },
            spec+: {
                type: this.values.service.type,
            },
        } else null,
    },

    nodejs_application(name):: $.application(name) {
        local this = self,

        values+:: {
            image+: {
                repository: 'node'
            },
            service+: {
                enabled: true,
                port: 81,
            },
            volumeMounts+: if this.configmap == null then {} else {
                config: { 
                    mountPath: '%s/config/production.json' % this.values.appDirectory,
                    subPath: 'configuration',
                }
            },
            volumes+: if this.configmap == null then {} else {
                config: kube.ConfigMapVolume(this.configmap)
            },

            appConfig: {},
            appDirectory: '/usr/src/app',
        },

        configmap: if this.values.appConfig != {} then kube.ConfigMap('%s-config' % name) {
            metadata+: {
                labels+: if this.values.extraLabels != {} then this.values.extraLabels else {},
            },
            data: { configuration: std.manifestJsonEx(this.values.appConfig, '  ') },
        } else null,
    },

    backstage_backend(name, namespace='backstage'):: {
        local backstage = self,

        appDir:: '/app',
        appPort:: 7000,
        baseUrl:: 'http://localhost',

        appConfigLocal:: {
            app: { baseUrl: backstage.baseUrl },
            backend: {
                baseUrl: backstage.baseUrl,
                listen: { port: backstage.appPort },
                cors: { origin: backstage.baseUrl },
                database: {
                    client: 'pg',
                    connection: {
                        host: "${POSTGRES_HOST}",
                        port: "${POSTGRES_PORT}",
                        user: "${POSTGRES_USER}",
                        password: "${POSTGRES_PASSWORD}"
                    },
                },
            },
        },

        database_secret: kube.Secret('%s-backstage-secrets' % name) {
            metadata+: {
                namespace: namespace
            },
            data_: {
                POSTGRES_HOST: backstage.database.service.metadata.name,
                POSTGRES_PORT: "5432",
                POSTGRES_USER: 'postgres',
                POSTGRES_PASSWORD: 'password',
            },
        },

        database_volume: kube.PersistentVolumeClaim('%s-postgres-vol' % name) {
            metadata+: {
                namespace: namespace
            },            
            storage: '2G',
        },

        database: $.application('%s-postgres' % name) {
            values+:: {
                namespace: namespace,
                healthCheck: '',
                image+: {
                    repository: 'postgres',
                    tag: '13.2-alpine'
                },
                service+: {
                    enabled: true,
                    port: 5432
                },
                environmentFrom+: [
                    kube.SecretRef(backstage.database_secret)
                ],
                volumeMounts+: {
                    postgresdb: { mountPath: '/var/lib/postgresql/data' }
                },
                volumes+: {
                    postgresdb: kube.PersistentVolumeClaimVolume(backstage.database_volume)
                },
            },
        },

        backend_config: kube.ConfigMap('%s-app-config' % name) {
            metadata+: { namespace: namespace },
            data: { 'app-config.local.yaml': std.manifestYamlDoc(backstage.appConfigLocal) },
        },

        backend: $.application('%s-backend' % name) {
            values+:: {
                namespace: namespace,
                healthCheck: '',
                podAnnotations: {
                    'local-config/checksum': std.md5(backstage.backend_config.data['app-config.local.yaml'])
                },
                image+: {
                    repository: 'backstage',
                    tag: '1.0.0'
                },
                service+: {
                    enabled: true,
                    port: 7000
                },
                environmentFrom+: [
                    kube.SecretRef(backstage.database_secret)
                ],
                volumeMounts+: {
                    local_config: { 
                        mountPath: '%s/app-config.local.yaml' % backstage.appDir, 
                        subPath: 'app-config.local.yaml' 
                    }
                },
                volumes+: {
                    local_config: kube.ConfigMapVolume(backstage.backend_config)
                },
            },   
        },
    },
}