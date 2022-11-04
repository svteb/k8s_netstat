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

  it "'helm' should install cnf" do
    # sample-cnfs/ndn-multi-db-connections-fail
    release_name = "wordpress"
    helm_namespace_option = nil
    helm_values = nil
    helm_chart_directory = "sample-cnfs/ndn-multi-db-connections-fail/wordpress"

    install_success = true

    begin
      resp = Helm.install(release_name, helm_chart_directory, helm_namespace_option, helm_values)
      Log.info { resp }
      install_success = (resp[:status].exit_status == 0)
    rescue e : Helm::InstallationFailed
      Log.fatal {"Helm installation failed"} 
      Log.fatal {"\t#{e.message}"} 
      install_success = false
    rescue e : Helm::CannotReuseReleaseNameError
      Log.info {"Release name #{release_name} has already been setup."}
      install_success = false
    end

    (install_success).should be_true
  ensure
    resp = Helm.uninstall(release_name)
    Log.info { resp }
    resp[:status].exit_status == 0
  end

end
