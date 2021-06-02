local pelotech = import '../lib/pelotech.libsonnet';

{
    app: pelotech.nodejs_application('configured') {
        values+:: {
            appConfig: { hello: 'world' },
        },
    },
}