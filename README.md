# pelotech-libsonnet
Pelotech Jsonnet Libraries

```bash
:pelotech-libsonnet$ jsonnet -y examples/myapp.jsonnet 
---
{
   "apiVersion": "apps/v1",
   "kind": "Deployment",
   "metadata": {
      "annotations": { },
      "labels": { },
      "name": "test",
      "namespace": "default"
   }
}
```

```bash
:pelotech-libsonnet$ kubecfg show examples/myapp.jsonnet 
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations: {}
  labels: {}
  name: test
  namespace: default
```