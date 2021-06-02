local kube = import 'kube.libsonnet';

{

    SimpleIngress(name):: {
        local this = self,

        target_service:: error 'target_service is required for ingress',

        values:: {
            labels: {},
            hosts: [],
            tls: {
                enabled: false,
                secretName: '',
                cert_manager: {
                    cluster_issuer: '',
                    issuer: ''
                },
            },
            ingress_class: error 'must specify an ingress class'
        },

        local tls_secret = if this.values.tls.secretName != '' then this.values.tls.secretName else '%s-tls' % name,

        assert std.length(this.values.hosts) != 0 : 'at least one host dictionary must be provided for ingress in the form of { name: "hostname.example.com", paths: ["/"] }. The "paths" key is optional and defaults to that shown.',
        assert !this.values.tls.enabled || (this.values.tls.cert_manager.cluster_issuer != '' || this.values.tls.cert_manager.issuer != '') : 'when tls is enabled for ingress, one of tls.cert_manager.cluster_issuer or values.tls.cert_manager.issuer must be provided',            

        ingress: kube._Object('extensions/v1beta1', "Ingress", name) {
            metadata+: {
                labels: this.values.labels,
                annotations: {
                    'kubernetes.io/ingress.class': this.values.ingress_class,  
                } + if this.values.tls.enabled && this.values.tls.cert_manager.cluster_issuer != '' then {
                    'cert-manager.io/cluster-issuer': this.values.tls.cert_manager.cluster_issuer
                } else if this.values.tls.enabled && this.values.tls.cert_manager.issuer != '' then {
                    'cert-manager.io/issuer': this.values.tls.cert_manager.issuer
                } else {},
            },
            spec: {
                tls: [
                    { 
                        hosts: [           
                            assert host.name != '' : 'ingress hosts dictionaries must contain a "name"';
                            host.name for host in this.values.hosts
                        ],
                        secretName: tls_secret
                    },
                ],
                rules: [
                    {
                        host: host.name,
                        http: {
                            paths: if !std.objectHas(host, 'paths') || std.length(host.paths) == 0 then [
                                { 
                                    path: '/', backend: { serviceName: this.target_service.metadata.name, servicePort: 'http' } 
                                },
                            ] else [
                                {
                                    path: path, backend: { serviceName: this.target_service.metadata.name, servicePort: 'http' },
                                } for path in host.paths
                            ],
                        }, 
                    } for host in this.values.hosts
                ],
            },
        }
    },

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
            ingress: {
                enabled: false,
                labels: this.values.extraLabels,
                hosts: [],
                tls: {
                    enabled: false,
                    secretName: '',
                    cert_manager: {
                        cluster_issuer: '',
                        issuer: ''
                    },
                },
                ingress_class: 'nginx-internal'
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

        assert this.values.service.enabled || this.values.ingress.enabled : 'ingress can only be enabled when service is enabled',

        ingress: if this.values.ingress.enabled then $.SimpleIngress(name) {
            target_service: this.service,
            values: this.values.ingress,
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