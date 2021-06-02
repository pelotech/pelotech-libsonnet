local pelotech = import '../lib/pelotech.libsonnet';

{
    app: pelotech.nodejs_application('configured') {
        values+:: {
            appConfig: { hello: 'world' },
            ingress+: {
                enabled: true,
                hosts: [
                    {
                        name: 'test.example.com',
                        paths: ['/'],
                    },
                ],
                tls: { 
                    enabled: true,
                    cert_manager: {
                        issuer: 'test'
                    },
                },
            },
        },
    },
}