local utils = import 'pelotech-utils.libsonnet';

{
    application(
        name,
        namespace='default',
        image='docker.io/node',
        tag='latest', 
        pull_policy='IfNotPresent',
        app_directory='/usr/src/app',
        service_type='ClusterIP',
        service_port=81,
    )::
    utils.deployment(name=name, namespace=namespace, image=image, tag=tag, pull_policy=pull_policy)
}