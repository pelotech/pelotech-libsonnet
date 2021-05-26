local object_meta(
        name,
        namespace='default',
        annotations={},
        labels={},
        ) = {
            name: name,
            namespace: namespace,
            annotations: annotations,
            labels: labels
        };

{

    deployment(
        name,
        namespace='default',
        annotations={},
        labels={},
        image='docker.io/node',
        tag='latest', 
        pull_policy='IfNotPresent',
    )::
        {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: object_meta(name=name, namespace=namespace, annotations=annotations, labels=labels)
    },
}