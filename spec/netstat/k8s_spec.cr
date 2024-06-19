require "kubectl_client"
require "helm"
require "cluster_tools"
require "../spec_helper"
require "../../src/netstat.cr"
require "../../src/netstat/k8s.cr"

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

    after_all do 
      resp = Helm.uninstall(release_name)
      KubectlClient::Delete.command("pvc/data-wordpress-mariadb-0")
      KubectlClient::Delete.command("pvc/wordpress")
      Log.info { resp }
      (resp[:status].exit_status == 0).should be_true
    end
    
    it "k8s_netstat should detect multiple pods conected to same db" do
      helm_install(release_name, helm_chart_directory)
      KubectlClient::Get.resource_wait_for_install(kind="Deployment", resource_name="wordpress", wait_count=180, namespace="default")
      violators = Netstat::K8s.get_multiple_pods_connected_to_mariadb_violators
      (Netstat::K8s.detect_multiple_pods_connected_to_mariadb_from_violators(violators)).should be_false
    end
  end
  
  describe "cnf with no database is used by two microservices" do
    # sample-cnfs/sample-statefulset-cnf
    release_name = "test"
    helm_chart = "bitnami/wordpress"

    before_all do
      Helm.helm_repo_add("bitnami", "https://charts.bitnami.com/bitnami")
    end

    after_all do 
      resp = Helm.uninstall(release_name)
      KubectlClient::Delete.command("pvc/data-wordpress-mariadb-0")
      KubectlClient::Delete.command("pvc/wordpress")
      Log.info { resp }
      (resp[:status].exit_status == 0).should be_true
    end
    
    it "k8s_netstat should detect mutiple pods NOT connected to same db" do
      helm_install(release_name, helm_chart, nil, "--set mariadb.primary.persistence.enabled=false --set persistence.enabled=false")
      KubectlClient::Get.resource_wait_for_install(kind="Deployment", resource_name="test-wordpress", wait_count=180, namespace="default")
      violators = Netstat::K8s.get_multiple_pods_connected_to_mariadb_violators
      (Netstat::K8s.detect_multiple_pods_connected_to_mariadb_from_violators(violators)).should be_false
    end
  end

end
