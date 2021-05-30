local pelotech = import '../lib/pelotech.libsonnet';

{
    app: pelotech.nodejs_application('configured') {
        config+:: {
            appConfig: { hello: 'world' },
        },
    },
}