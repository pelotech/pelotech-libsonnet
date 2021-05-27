local pelotech = import '../pelotech.libsonnet';

{
    app: pelotech.nodejs_application('defaults') {
        config+: {
            appConfig: { hello: 'world' },
        },
    },
}