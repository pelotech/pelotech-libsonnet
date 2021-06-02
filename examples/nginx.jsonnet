local pelotech = import '../lib/pelotech.libsonnet';

pelotech.application('nginx') {
    values+:: {
        image+: { repository: 'nginx' },
        service+: { enabled: true, port: 80 },
        ingress+: { enabled: true, hosts: [ { name: 'nginx.example.com' } ] },
    },
}