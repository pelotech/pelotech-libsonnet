local pelotech = import 'lib/pelotech.libsonnet';

function(name, values={}) {
    app: pelotech.application(name)
}