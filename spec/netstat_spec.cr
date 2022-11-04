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
  
  describe "cnf with two services on the cluster that connect to the same database" do
    # sample-cnfs/ndn-multi-db-connections-fail
    release_name = "wordpress"
    helm_chart_directory = "sample-cnfs/ndn-multi-db-connections-fail/wordpress"

    it "should install" do
      helm_install(release_name, helm_chart_directory)
    end
  ensure
    resp = Helm.uninstall(release_name)
    Log.info { resp }
    resp[:status].exit_status == 0
  end
  
  describe "cnf with two services on the cluster that connect to the same database" do
  # sample-cnfs/sample-statefulset-cnf
    Helm.helm_repo_add("bitnami", "https://charts.bitnami.com/bitnami")
    release_name = "test"
    helm_chart = "bitnami/wordpress"

    it "should install" do
      helm_install(release_name, helm_chart, nil, "--set mariadb.primary.persistence.enabled=false --set persistence.enabled=false")
    end
  ensure
    resp = Helm.uninstall(release_name)
    Log.info { resp }
    resp[:status].exit_status == 0
  end

end
