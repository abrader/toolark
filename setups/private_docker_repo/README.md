## Private Docker Registry on DC/OS with Marathon-LB

### Create certificate and key pair

Run `registry/registry_cert_gen.sh`

This will create
- `domain.crt`
- `domain.key`
- `registry.pem`

We will need these for later

### Serve up crt, key, and pem via Bootstrap node

On the bootsrap server, copy the crt, key, and pem files
into a directory that is self contained.  Then within that
directory, run the following command:

````BASH
docker run -d -p 8085:80 -v $PWD:/usr/share/nginx/html:ro nginx
````

This will make those files accessible on
`http://boostrap:8085/{domain.crt,domain.key,registry.pem}`

### Modify [registry.json](registry.json)

Pin Docker Registry to private agent (ex: 172.28.5.21):

````JSON
"constraints": [
    [
      "hostname",
      "LIKE",
      "172.28.5.21"
    ]
  ],
````
You must specify where the registry serves the containers
from.  DC/OS will bark at you if this is not supplied and if this is invalid, your Docker Registry will not start.
Alter the `hostPath` directive:

````JSON
"volumes": [
  {
    "containerPath": "/var/lib/registry",
    "hostPath": "/vagrant/regstore",
    "mode": "RW"
  }
],
````

Fetch requests should either point to local files for both files:

- `domain.crt`
- `domain.key`

If file, use `file:///blah` otherwise adjust IP addresses in followig section
to point to accessible webserver (i.e., simple NGINX container):

````JSON
"fetch": [
  {
    "uri": "http://172.28.5.2:8085/domain.crt",
    "extract": true,
    "executable": false,
    "cache": false
  },
  {
    "uri": "http://172.28.5.2:8085/domain.key",
    "extract": true,
    "executable": false,
    "cache": false
  }
],
````

Lastly, alter HAProxy vhost directive to point to same
public agent IP as in the constraints section:

````JSON
"labels": {
  "HAPROXY_GROUP": "internal",
  "HAPROXY_0_SSL_CERT": "/mnt/mesos/sandbox/registry.pem",
  "HAPROXY_0_BACKEND_REDIRECT_HTTP_TO_HTTPS": "false",
  "HAPROXY_0_VHOST": "172.28.5.21"
},
````

### Modify [marathon-lb-internal.json](marathon-lb-internal.json) file

We want the `name` directive to represent the hostname you want to use for the LB:

````JSON
{
    "marathon-lb": {
        "name": "shared/marathon-lb-internal",
        "bind-http-https": false,
        "haproxy-group": "internal",
        "role": ""
    }
}
````

### Distribute keys to all private nodes

Replace `<bootstrap>` with the IP/DNS name of disable_mesos_authentication of NGINX container serving
crt, key, and pem.

````BASH
DOMAIN_NAME=marathon-lb-internal.shared.marathon.mesos
PORT=10050
BOOT_WEB_URL="http://<bootstrap-ip>:8085"

echo "Adding cert from ${DOMAIN_NAME} to the local CA trust"
wget ${BOOT_WEB_URL}/{domain.crt,registry.pem}
echo "Adding cert from ${DOMAIN_NAME} to the list of trusted certs"
sudo cp domain.crt /etc/pki/ca-trust/source/anchors/${DOMAIN_NAME}.crt
sudo mkdir -p /etc/docker/certs.d/${DOMAIN_NAME}:${PORT}
sudo cp domain.crt /etc/docker/certs.d/${DOMAIN_NAME}:${PORT}/ca.crt
sudo update-ca-trust
systemctl restart docker
````

### Run marathon-lb

`dcos package install --options=mlbint.json marathon-lb --yes`

Shortly after you see this running in the DC/OS UI, you will want to add the followig artifact to marathon-lb:

`http://172.28.5.2:8085/registry.pem`

Replace `172.28.5.2` with the IP of your NGINX container

Once this is replaced click `Run` in the DC/OS UI to
redploy marathon-lb.  Failure to complete this step will
cause your LB to give you `Connection Refused` messages.

### Run Docker Registry

Run the following command:

`dcos marathon app add registry.json`

### Test setup

Run the following command by using the **system** curl:

````BASH
curl https://marathon-lb-internal.shared.marathon.mesos:10050/v2/_catalog
````

### Install certs for Fetcher use

Copy PEM:

````BASH
cp registry.pem to /var/lib/dcos/pki/tls/certs
````
Get a Hash for that PEM:

````BASH
openssl x509 -hash -noout -in /var/lib/dcos/pki/tls/certs/registry.pem
````

In my case that hash = `b75f97a2`.  We take that hash
and create a symbolic link.  You **MUST** append `.0` to the link:

````BASH
ln -s /var/lib/dcos/pki/tls/certs/registry.pem b75f97a2.0
````

### Test certs for Fetcher use

Assuming you have done everything else correctly, the following command should return a value other than a cURL
SSL error.

Run the following command using the vendored **Mesosphere** curl:

````BASH
/opt/mesosphere/bin/curl https://marathon-lb-internal.shared.marathon.mesos:10050/v2/_catalog
````

In my case, that returned the following:

`{"repositories":[]}`

---

*fin*
