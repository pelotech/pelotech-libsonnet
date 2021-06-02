local pelotech = import '../lib/pelotech.libsonnet';

{
    app: pelotech.nodejs_application('defaults')
}