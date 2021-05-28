local pelotech = import '../pelotech.libsonnet';

{
    backend: pelotech.backstage('backstage') {
        baseUrl: 'http://localhost:7000',
    },
}