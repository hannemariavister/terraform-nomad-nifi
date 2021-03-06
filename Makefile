include dev/.env
export PATH := $(shell pwd)/tmp:$(PATH)

.ONESHELL .PHONY: up update-box destroy-box remove-tmp clean example
.DEFAULT_GOAL := up

#### Pre requisites ####
install:
	 mkdir -p tmp;(cd tmp; git clone --depth=1 https://github.com/fredrikhgrelland/vagrant-hashistack.git; cd vagrant-hashistack; make install); rm -rf tmp/vagrant-hashistack

check_for_consul_binary:
ifeq (, $(shell which consul))
	$(error "No consul binary in $(PATH), download the consul binary from here :\n https://www.consul.io/downloads\n\n' && exit 2")
endif

check_for_terraform_binary:
ifeq (, $(shell which terraform))
	$(error "No terraform binary in $(PATH), download the terraform binary from here :\n https://www.terraform.io/downloads.html\n\n' && exit 2")
endif

check_for_docker_binary:
ifeq (, $(shell which docker))
	$(error "No docker binary in $(PATH), install docker from here :\n https://docs.docker.com/get-docker/\n\n' && exit 2")
endif

#### Development ####
# Builds a vagrant box (included Ansible playbooks) for example/standalone, without running the tests.
dev-standalone: update-box custom_ca
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} CUSTOM_CA=${CUSTOM_CA} ANSIBLE_ARGS='--skip-tags "test" --extra-vars "\"mode=standalone\""' vagrant up --provision

# Builds a vagrant box (included Ansible playbooks) for example/standalone_git, without running the tests.
# Remember the parameters for GIT integration explained in /example/standalone_git/README.md
# Example: make dev repo=<GitHub-repository> branch=<branch to checkout and track> user=<GitHub username> token=<personal token from GitHub>
dev: check-params update-box custom_ca
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} CUSTOM_CA=${CUSTOM_CA} ANSIBLE_ARGS='--skip-tags "test" --extra-vars "\"mode=standalone_git repo=$(repo) branch=${branch} user=${user} token=${token}\""' vagrant up --provision

custom_ca:
ifdef CUSTOM_CA
	cp -f ${CUSTOM_CA} docker/conf/certificates/
endif

# Builds the vagrant box and the example/standalone
up-standalone: update-box custom_ca
ifeq ($(GITHUB_ACTIONS),true) # Always set to true when GitHub Actions is running the workflow. You can use this variable to differentiate when tests are being run locally or by GitHub Actions.
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} ANSIBLE_ARGS='--extra-vars "\"ci_test=true mode=standalone\""' vagrant up --provision
else
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} CUSTOM_CA=${CUSTOM_CA} ANSIBLE_ARGS='--extra-vars "\"mode=standalone\""' vagrant up --provision
endif

# Builds the vagrant box and the example/standalone_git
# Remember the parameters for GIT integration explained in /example/standalone_git/README.md
# Example: make up repo=<GitHub-repository> branch=<branch to checkout and track> user=<GitHub username> token=<personal token from GitHub>
up: check-params update-box custom_ca
ifeq ($(GITHUB_ACTIONS),true) # Always set to true when GitHub Actions is running the workflow. You can use this variable to differentiate when tests are being run locally or by GitHub Actions.
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} ANSIBLE_ARGS='--extra-vars "\"ci_test=true mode=standalone_git repo=$(repo) branch=${branch} user=${user} token=${token}\""' vagrant up --provision
else
	SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} CUSTOM_CA=${CUSTOM_CA} ANSIBLE_ARGS='--extra-vars "\"mode=standalone_git repo=$(repo) branch=${branch} user=${user} token=${token}\""' vagrant up --provision
endif

# Checks that all parameters are set.
check-params:
	@[ "${repo}" ] || ( echo ">> The parameter repo is not defined. repo=<GitHub-repository, use HTTPS>" )
	@[ "${branch}" ] || ( echo ">> The parameter branch is not defined. branch=<branch to checkout and track>")
	@[ "${user}" ] || (  echo ">> The parameter user is not defined. user=<GitHub username>")
	@[ "${token}" ] || ( echo ">> The parameter token is not defined. token=<personal token from GitHub" )
	@[ "${repo}" ] && [ "${branch}" ] && [ "${user}" ] && [ "${token}" ]|| (echo "See README.md for more details and example: https://github.com/hannemariavister/terraform-nomad-nifi/blob/master/example/standalone_git/README.md" ; exit 1 )

# Runs through your Ansible Playbook tests and builds up /example/standalone
test-standalone: clean up-standalone

# Runs through your Ansible Playbook tests and builds up /example/standalone_git (remember the parameters for GIT integration explained in /example/standalone_git/README.md).
# Example: make test repo=<GitHub-repository> branch=<branch to checkout and track> user=<GitHub username> token=<personal token from GitHub>
test: clean up

template_example: custom_ca
ifeq ($(GITHUB_ACTIONS),true) # Always set to true when GitHub Actions is running the workflow. You can use this variable to differentiate when tests are being run locally or by GitHub Actions.
	cd template_example; SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} ANSIBLE_ARGS='--extra-vars "ci_test=true"' vagrant up --provision
else
	if [ -f "docker/conf/certificates/*.crt" ]; then cp -f docker/conf/certificates/*.crt template_example/docker/conf/certificates; fi
	cd template_example; SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} CUSTOM_CA=${CUSTOM_CA} vagrant up --provision
endif

status:
	vagrant global-status

# clean commands
destroy-box:
	vagrant destroy -f

remove-tmp:
	rm -rf ./tmp
	rm -rf ./.vagrant
	rm -rf ./.minio.sys
	rm -rf ./example/.terraform
	rm -rf ./example/terraform.tfstate
	rm -rf ./example/terraform.tfstate.backup

clean: destroy-box remove-tmp

# helper commands
update-box:
	@SSL_CERT_FILE=${SSL_CERT_FILE} CURL_CA_BUNDLE=${CURL_CA_BUNDLE} vagrant box update || (echo '\n\nIf you get an SSL error you might be behind a transparent proxy. \nMore info https://github.com/fredrikhgrelland/vagrant-hashistack/blob/master/README.md#proxy\n\n' && exit 2)

pre-commit: check_for_docker_binary check_for_terraform_binary
	docker run -e RUN_LOCAL=true -v "${PWD}:/tmp/lint/" github/super-linter
	terraform fmt -recursive && echo "\e[32mTrying to prettify all .tf files.\e[0m"

# consul-connect proxy to service
# required binary `consul` https://releases.hashicorp.com/consul/
proxy-nifi:
	consul intention create -token=master nifi-local nifi
	consul connect proxy -token master -service nifi-local -upstream nifi:8182 -log-level debug

proxy-nifi-reg:
	consul intention create -token=master nifi-registry-local nifi-registry
	consul connect proxy -token master -service nifi-registry-local -upstream nifi-registry:18080 -log-level debug

