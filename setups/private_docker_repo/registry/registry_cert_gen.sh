REPO_URL=marathon-lb-internal.shared.marathon.mesos
echo "Generating key, crt and pem file for ${REPO_URL}"
openssl req -newkey rsa:4096 -nodes -sha256 \
 -keyout domain.key  -x509 -days 365 \
 -out domain.crt \
 -subj "/C=US/ST=Florida/L=Miami/O=IT/CN=${REPO_URL}"
echo "Generating pem"
cat domain.crt domain.key | tee registry.pem
