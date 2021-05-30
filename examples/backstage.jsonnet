local pelotech = import '../lib/pelotech.libsonnet';


function(values={}) {
    backend: pelotech.backstage_backend('backstage') {
        baseUrl: 'http://localhost:7000',
    },
}