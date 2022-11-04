require "kubectl_client"
require "helm"
require "cluster_tools"
require "./spec_helper"
require "./../src/netstat.cr"

describe "netstat" do
  before_all do
    begin
      KubectlClient::Create.namespace("cnf-testsuite")
    rescue e : KubectlClient::Create::AlreadyExistsError
    end
    ClusterTools.install
  end

  it "'helm' should install cnf with two services on the cluster that connect to the same database" do
    # sample-cnfs/ndn-multi-db-connections-fail
    release_name = "wordpress"
    helm_chart_directory = "sample-cnfs/ndn-multi-db-connections-fail/wordpress"
    install_success = true
    helm_install(release_name, helm_chart_directory)
  ensure
    resp = Helm.uninstall(release_name)
    Log.info { resp }
    resp[:status].exit_status == 0
  end
  
  # sample-cnfs/sample-statefulset-cnf
  it "'helm' should install cnf with no database used by two microservices" do
    # sample-cnfs/ndn-multi-db-connections-fail
    Helm.helm_repo_add("bitnami", "https://charts.bitnami.com/bitnami")
    release_name = "test"
    helm_chart = "bitnami/wordpress"
    install_success = true
    helm_install(release_name, helm_chart, nil, "--set mariadb.primary.persistence.enabled=false --set persistence.enabled=false")
  ensure
    resp = Helm.uninstall(release_name)
    Log.info { resp }
    resp[:status].exit_status == 0
  end

end
