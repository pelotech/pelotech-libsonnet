local kube = import 'https://github.com/bitnami-labs/kube-libsonnet/raw/v1.14.6/kube.libsonnet';

local utils = {
    makeKey(key):: std.join('', std.flattenArrays([
        if std.codepoint(c) >= 97 then [std.asciiUpper(c)]
        else ['_', c]
        for c in std.stringChars(key)
    ])),

    toDot(key):: std.join('', 
        std.flattenArrays(
            [
                if std.codepoint(c) >= 97 then [c]
                else ['.', std.asciiLower(c)]
                for c in std.stringChars(key)
            ]
        )
    ),

    makeSection(key):: 
        local toDot = $.toDot(key);
        local split = std.split(toDot, '.');
        local length = std.length(split);
        if length <= 2 then toDot
        else std.format('%s.%s', [split[0], std.join('_', std.slice(split, 1, length, 1))]),

    walkConfig(config, parent):: if parent == '' then {
        main: {
            [$.makeKey(key)]: config[key]
            for key in std.objectFields(config)
            if std.type(config[key]) != 'object'
        },
        sections: {
            [$.makeSection(key)]: $.walkConfig(config, key)
            for key in std.objectFields(config)
            if std.type(config[key]) == 'object'
        },
    } else {
        [$.makeKey(key)]: config[parent][key],
        for key in std.objectFields(config[parent])
    },

    makeIniConfig(config):: std.manifestIni($.walkConfig(config, '')),
};

{
    local gogs = self,

    name_prefix:: 'gogs',
    namespace_:: 'gogs',
    create_namespace:: true,

    version:: '0.12.3',

    config:: {
        local config = self,
        
        format():: config {
            security+: { secretKey: std.base64(config.security.secretKey) },
        },

        appName: 'Gogs',
        runMode: 'prod',
        repositoryUpload: {
            enabled: true,
            allowedType: null,
            maxFilesSize: 3,
            maxFiles: 5
        },
        server: {
            protocol: 'http',
            domain: 'gogs.example.com',
            rootUrl: 'http://gogs.example.com/',
            landingPage: 'home',
            sshDomain: self.domain,
            sshPort: gogs._container_ssh_port,
            sshListenPort: gogs._container_ssh_port
        },
        service: {
            activeCodeLiveMinutes: 180,
            resetPasswdCodeLiveMinutes: 180,
            enableCaptcha: true,
            registerEmailConfirm: false,
            disableRegistration: false,
            requiresSigninView: false,
            enableNotifyMail: false,
            enableReverseProxyAuthentication: false,
            enableReverseProxyAutoRegistration: false
        },
        mailer: {
            enabled: false,
            host: '',
            disableHelo: false,
            heloHostname: '',
            skipVerify: false,
            subjectPrefix: '',
            from: '',
            user: '',
            passwd: '',
            usePlainText: 'text/plain'
        },
        database: {
            dbType: 'postgres',
            host: '',
            name: '',
            user: '',
            passwd: '',
            sslMode: 'disable'
        },
        security: {
            installLock: true,
            secretKey: 'changeme' // base64
        },
        ui: {
            explorePagingNum: 20,
            issuePagingNum: 10,
            feedMaxCommitNum: 5
        },
        cache: {
            adapter: 'memory',
            interval: '60',
            host: ''
        },
        webhook: {
            queueLength: 1000,
            deliverTimeout: 5,
            skipTlsVerify: true, // maybe be false by default
            pagingNum: 10
        },
        log: {
            mode: 'console',
            // Either "Trace", "Info", "Warn", "Error", "Fatal"
            level: 'Info'
        },
        cron: {
            enabled: true,
            runAtStart: false,
        },
        cronUpdateMirrors: {
            schedule: '@every 10m'
        },
        cronRepoHealthCheck: {
            schedule: '@every 24h',
            timeout: '60s',
            args: ''
        },
        cronCheckRepoStats: {
            runAtStart: true,
            schedule: '@every 24h'
        },
        cronRepoArchiveCleanup: {
            runAtStart: false,
            schedule: '@every 24h',
            olderThan: '24h'
        },
        other: {
            showFooterBranding: false,
            showFooterVersion: true,
            showFooterTemplateLoadTime: true
        },
    },

    _getHealthPath():: if gogs.config.service.requiresSigninView then '/user/login' else '/',

    _container_http_port:: 3000,
    _container_ssh_port:: 22,

    _probe:: {
        initialDelaySeconds: 180,
        httpGet: {
            path: gogs._getHealthPath(),
            port: gogs._container_http_port
        }
    },

    _labels:: {
        app: 'gogs',
        component: 'server'
    },

    // BEGIN RESOURCES

    // The namespace
    namespace: if gogs.create_namespace then kube.Namespace(gogs.namespace_) else null,

    // The Gogs configuration
    configmap: kube.ConfigMap(gogs.name_prefix + '-config') {
        metadata+: { 
            namespace: gogs.namespace_,
            labels: gogs._labels,
        },
        data: {
            'app.ini': utils.makeIniConfig(gogs.config.format()) 
        }
    },

    // The Deployment object
    deployment: kube.Deployment(gogs.name_prefix + '-deployment') {
        metadata+: {
            namespace: gogs.namespace_,
            labels: gogs._labels
        },
        spec+: {
            replicas: 1,
            strategy: { type: 'RollingUpdate' },
            minReadySeconds: 10,
            template+: {
                metadata+: {
                    annotations: {
                        'gogs/config-checksum': std.md5(gogs.configmap.data['app.ini'])
                    },
                },
                spec+: {
                    terminationGracePeriodSeconds: 10,
                    containers_+: {
                        app: kube.Container('gogs') {
                            image: 'gogs/gogs:%s' % gogs.version,
                            imagePullPolicy: 'IfNotPresent',
                            env_+: {
                                SOCAT_LINK: 'false'
                            },
                            ports_+: { 
                                http: { containerPort: gogs._container_http_port },
                                ssh: { containerPort: gogs._container_ssh_port },
                            },
                            livenessProbe: gogs._probe,
                            readinessProbe: gogs._probe,
                            volumeMounts: {
                                data: { mountPath: '/data' },
                                config: { mountPath: '/data/gogs/conf/app.ini', subPath: 'app.ini' },
                            }
                        },
                    },
                    volumes: {
                        data: kube.EmptyDirVolume(),
                        config: kube.ConfigMapVolume(gogs.configmap)
                    }
                },
            },
        },
    }

}