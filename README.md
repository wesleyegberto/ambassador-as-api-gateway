# Steps to setup Ambassador as API Gateways

This is a resume from a bunch of links (see Links and References section to see the sources).

## PreFly:

### Minikube
Install from [here](https://github.com/kubernetes/minikube).

Get Cluster IP
* `minikube ip`

To by-pass proxy:
* `export no_proxy=$no_proxy,$(minikube ip)`


### GCP and Minikube
Check if Kubernetes has RBAC:
* `kubectl cluster-info dump --namespace kube-system | grep authorization-mode`

If it has we should use the file `ambassador-rbac.yaml`, otherwise use `ambassador-no-rbac.yaml`

When using GCP with RBAC we need to grant `cluster-admin` role privileges, we can execute:
* `kubectl create clusterrolebinding my-cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud info --format="value(config.account)")`



## Checking stuff
To check if the Pods and Services were created:
* `kubectl get pod,svc`


## Conventions
Some conversion in this steps.
* <MINIKUBE_IP>: replace by Minikube Cluster IP (usually 192.168.99.100)
* <AmbassadorAdmin_Service_Port>: replace by Ambassador-Admin service port
* <Ambassador_Service_Port>: replace by Ambassador service port



## Start the applications

Deploy the applications:
* `kubectl apply -f shopfront-service.yml`
* `kubectl apply -f productcatalogue-service.yml`
* `kubectl apply -f stockmanager-service.yml`


Check the Pods are running and the Service's Port, because our Services are of type ClusterIP we can't reache them from outside, you could create another service with type of NodePort and run the following command to see if it is runnig:
* Linking in the pod: `kubectl port-forwarding <pod_name> 8010:8010`
* Calling it (or open the browser): `curl -v localhost:8010`



## Deploy API Gateway
We will expose only the service which is meant to be public (the shopfront service).

### Create LoadBalancer service with routes
First create a service of type LoadBalancer that uses Kubernetes annotations to route requests from outside the cluster to the appropriate services
Before apply remove the entry **authentication** from the `ambassador-service.yml`.

* `kubectl apply -f ambassador-service.yml`

Notes about the YML:
* **getambassador.io/config: |**: specifies that this annotation is for Ambassador
* **apiVersion: ambassador/v0**: specifies the Ambassador API/schema version
* **kind: Mapping**: specifies that you are creating a “mapping” (routing) configuration
* **name: shopfront**: is the name for this mapping (which will show up in the debug UI)
* **prefix: /shopfront/**: is the external prefix of the URI that you want to route internally
* **service: shopfront:8010**: is the Kubernetes service (and port) you want to route to


### Create Ambassador components
With that we have our mapping but we need to deploy the Ambassador Admin and its containers that will do the heavy work.
Execute the version (rbac or no-rbac) accordly to prefly check.
* `kubectl apply -f ambassador-rbac.yaml` or `kubectl apply -f ambassador-no-rbac.yaml`


We can access Ambassador Diagnostic Overview using:
* `http://<MINIKUBE_IP>:<AmbassadorAdmin_Service_Port>/ambassador/v0/diag/`
On it we an see the routes, weights, configs and healths.


We can access the application using:
* `http://<MINIKUBE_IP>:<Ambassador_Service_Port>/shopfront/`



## Adding Authentication

Ambassador uses a service to authenticate the requests, in this lab we use an HTTP Basic Authentication and database file YML with users.
This file is provided to our pod thought Kubernetes Secret.

Ambassador routes all requests through the authentication service: it relies on the auth service to distinguish between requests that need authentication and those that do not. If it can't connect to authentication service then will return a 503 for the request.
So it is mandatory to authentication service be up and running so ambassador can correctly use it.


### Create User and update Secrete database
Execute the script to encrypt the password using BCrypt.
* Install BCrypt: `pip instapp bcrypt`
* Encrypt our password: `./create_string_to_secret.sh my-plaintext-unsafe-password`
* Append the outputed string in the _ambassador_users.yml_ adding a new entry.

To put the file in Kubernetes Secret we need first encode it using Base64 (because Secret use Base64 data blob) and then update our secret file.
* Encode: `cat k8s_secret_users.yml | openssl base64 -A`
* Update the Secret entry (data.users.yaml) with the output from encoding
* Apply the change to Kubernetes: `kubectl apply -f k8s_secret_users.yml`


To test it we can link our host port to pod port and execute a cURL:
* Linkin: `kubectl port-fowarding <pod_auth_name> 9191:5000`
* cURL: `curl -v <username>:<password> localhost:9191/extauth`
* If we get a HTTP 200 then our user is ok, otherwise something is wrong


### Deploy the authenticator service

Deploy the pod and service: `kubectl apply -f ambassador-auth-http.yml`


### Update the route mapping

Add the following content to annotation section of YML.
```
---
apiVersion: ambassador/v0
kind: AuthService
name: authentication
auth_service: "ambassador-auth:80"
path_prefix: "/extauth"
allowed_headers: []
```

Then update the Ambassador service:

`kubectl apply -f ambassador-service.yml`

On Ambassador Diagnostic View you can see something like this:
```
http://192.168.99.100:32185/shopfront/          shopfront-canary:8010      50.0%
                                                shopfront:8010	           50.0% 
```


### Testing

Try to access the Shopfront to see if it will prompt for user and password.
We can also test using cURL:
* Unauthorized: `curl -v http://<MINIKUBE_IP>:<Ambassador_Service_Port>/httpbin`
* Authorized: `curl -v -u johndue:password http://<MINIKUBE_IP>:<Ambassador_Service_Port>/httpbin`



## Canary Release
To add canary support we just need to "overload" our path application in our route mapping and add a **weight** to its canary path.


### Deploy the canary version

Deploy the canary version of the application and the service:
* `k apply -f shopfront-service-canary.yml`


## Update the routes

Add the following content to annotation section of YML.
```
---
apiVersion: ambassador/v0
kind:  Mapping
name:  shopfront_canary
prefix: /shopfront/
weight: 50
service: shopfront-canary:8010
```

Note the line with `weight: 50`, it tells the Ambassador to route 50% of traffic to it.

Then update the Ambassador service:
* `kubectl apply -f ambassador-service.yml`


## Testing
To test just access the Shopfront URl and keep hiting F5 to see the two versions (the canary has a red banner on top).
* `http://<MINIKUBE_IP>:<Ambassador_Service_Port>/shopfront/`

It also can use header to route the request to specific service.


## Notes

* If the LoadBalancer gets stuck on status `<pending>` doesn't matter, you can still call it using localhost (check [here](https://www.datawire.io/docker-mac-kubernetes-ingress/)).



## Links and References

* https://www.envoyproxy.io/docs/envoy/latest/start/distro/ambassador
* https://www.getambassador.io/user-guide/getting-started
* https://www.getambassador.io/user-guide/auth-tutorial
* https://dzone.com/articles/deploying-java-apps-with-kubernetes-and-the-ambass
* https://github.com/datawire/ambassador-auth-httpbasic


# License

Licensed under Apache 2.0. Please read [LICENSE](LICENSE) for details.
