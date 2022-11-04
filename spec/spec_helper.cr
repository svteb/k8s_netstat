require "spec"
require "helm"

def helm_install(release_name : String, helm_chart_or_directory : String, helm_namespace_option = nil, helm_values = nil)
    install_success = true

    begin
      resp = Helm.install(release_name, helm_chart_or_directory, helm_namespace_option, helm_values)
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
end