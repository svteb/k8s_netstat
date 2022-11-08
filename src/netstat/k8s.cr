module Netstat
  module K8s
    def self.get_all_non_db_service_pod_ips
      cnf_services = KubectlClient::Get.services(all_namespaces: true)
      Log.info { "first cnf_services: #{cnf_services}" }

      pods = self.get_mariadb_pods_by_digest

      db_pod_ips = self.get_pods_ips(pods)

      Log.info { "DB Pods: #{db_pods_ips}" }

      # get all pod_ips by first cnf service that is not the database service
      all_service_pod_ips = [] of Array(NamedTuple(service_group_id: Int32, pod_ips: Array(JSON::Any)))

      cnf_services["items"].as_a.each_with_index do |cnf_service, index|
        service_pods = KubectlClient::Get.pods_by_service(cnf_service)
        if service_pods
          all_service_pod_ips << service_pods.map { |pod|
            {
              service_group_id: index,
              pod_ips:          pod.dig("status", "podIPs").as_a.select { |ip|
                db_pod_ips.select { |dbip| dbip["ip"].as_s != ip["ip"].as_s }
              },
            }
          }.flatten.compact
        end
      end

      all_service_pod_ips
    end

    def self.detect_multiple_pods_connected_to_same_db_from_pod_id_and_node(id, cluster_tools_node)
      parsed_netstat = self.get_pod_network_info_from_node_via_pod_id(id, cluster_tools_node)
      self.detect_multiple_pods_connected_to_same_db_from_parsed_netstat(parsed_netstat)
    end

    # # the response for this should be true for one of the cnfs and false for the other
    # # once we can test that works then we can test the interim steps
    def self.detect_multiple_pods_connected_to_same_db_from_parsed_netstat(parsed_netstat)
      all_service_pod_ips = self.get_all_non_db_service_pod_ips

      integrated_database_found = false
      filtered_local_address = parsed_netstat.reduce([] of NamedTuple(proto: String,
        recv: String,
        send: String,
        local_address: String,
        foreign_address: String,
        state: String)) do |acc, x|
        if x[:local_address].includes?("3306")
          acc << x
        else
          acc
        end
      end

      Log.info { "filtered_local_address: #{filtered_local_address}" }
      # todo filter for ips that belong to the cnf
      filtered_foreign_addresses = filtered_local_address.reduce([] of NamedTuple(proto: String,
        recv: String,
        send: String,
        local_address: String,
        foreign_address: String,
        state: String)) do |acc, x|
        ignored_ip = all_service_pod_ips[0]["pod_ips"].find { |i| x[:foreign_address].includes?(i["ip"].as_s) }
        if ignored_ip
          Log.info { "dont add: #{x[:foreign_address]}" }
          acc
        else
          Log.info { " add: #{x[:foreign_address]}" }
          acc << x
        end
        acc
      end
      Log.info { "filtered_foreign_addresses: #{filtered_foreign_addresses}" }
      # todo if count on uniq foreign ip addresses > 1 then fail
      # only count violators if they are part of any service, cluster wide
      violators = all_service_pod_ips.reduce([] of Array(JSON::Any)) do |acc, service_group|
        acc << service_group["pod_ips"].select do |spip|
          Log.info { " service ip: #{spip["ip"].as_s}" }
          filtered_foreign_addresses.find do |f|
            f[:foreign_address].includes?(spip["ip"].as_s)
            # f[:foreign_address].includes?(spip["ip"].as_s) ||
            #   # 10-244-0-8.test-w:34702
            #   f[:foreign_address].includes?(spip["ip"].as_s.gsub(".","-"))

          end
        end
      end

      violators = violators.flatten.compact

      Log.info { "violators: #{violators}" }

      violators
    end

    def self.get_pod_network_info_from_node_via_pod_id(id, cluster_tools_node)
      inspect = ClusterTools.exec_by_node("crictl inspect #{id}", cluster_tools_node)
      pid = JSON.parse(inspect[:output]).dig("info", "pid")
      Log.info { "Container PID: #{pid}" }
      # get multiple call for a larger sample
      parsed_netstat = (1..10).map {
        sleep 10
        netstat = ClusterTools.exec_by_node("nsenter -t #{pid} -n netstat -n", cluster_tools_node)
        Log.info { "Container Netstat: #{netstat}" }
        Netstat.parse(netstat[:output])
      }.flatten.compact
      # Log.info { "Container Netstat: #{netstat}"}
      # parsed_netstat = Netstat.parse(netstat[:output])
      # Log.info { "Container Netstat: #{parsed_netstat}"}
      # todo filter for 3306 in local_address
    end

    def self.get_pods_network_info_from_node_via_container_status(status)
      Log.info { "Container Info: #{status}" }
      # get network information on the node for each database pod
      cluster_tools_node = ClusterTools.pod_by_node("#{status["nodeName"]}")
      Log.info { "Container Tools Pod: #{cluster_tools_node}" }

      status["ids"].map do |id|
        self.get_pod_network_info_from_node_via_pod_id(id, cluster_tools_node_name)
      end
    end

    def self.netstat_container_statuses(container_statuses)
      Log.info { "Container Statuses: #{database_container_statuses}" }

      database_container_statuses.map do |status|
        self.get_pods_network_info_from_node_via_container_status(status)
      end
    end

    def self.detect_multiple_pods_connected_to_mariadb
      database_container_statuses = self.get_mariadb_pod_container_statuses
      parsed_netstats = netstat_container_statuses(database_container_statuses)

      integrated_database_found = false

      parsed_netstats.each do |pn|
        violators = self.detect_multiple_pods_connected_to_same_db_from_parsed_netstat(pn)

        if violators.size > 1
          integrated_database_found = true
        end
      end

      integrated_database_found
    end

    def self.get_mariadb_pod_container_statuses
      db_pods = self.get_mariadb_pods_by_digest

      pod_statuses = self.get_pods_statuses(db_pods)

      database_container_statuses = self.get_pods_container_statuses(pod_statuses)
    end

    def self.get_mariadb_pods_by_digest
      db_match = Mariadb.match
      Log.info { "DB Digest: #{db_match[:digest]}" }
      KubectlClient::Get.pods_by_digest(db_match[:digest])
    end

    def self.get_pods_statuses(pods)
      pod_statuses = pods.map { |i|
        {
          "statuses" => i.dig("status", "containerStatuses"),
          "nodeName" => i.dig("spec", "nodeName"),
        }
      }.compact

      Log.info { "Pod Statuses: #{pod_statuses}" }

      pod_statuses
    end

    def self.get_pods_ips(pods)
      Log.info { "DB Pods: #{db_pods}" }

      db_pod_ips = [] of Array(JSON::Any)

      db_pods.map { |i|
        db_pod_ips << i.dig("status", "podIPs").as_a
      }

      db_pod_ips = db_pod_ips.compact.flatten

      Log.info { "db_pod_ips: #{db_pod_ips}" }
      db_pod_ips
    end

    def self.get_pods_container_statuses(pod_statuses)
      container_statuses = pod_statuses.map do |statuses|
        filterd_statuses = statuses["statuses"].as_a.select { |x|
          x.dig("ready").as_bool &&
            x && x.dig("imageID").as_s.includes?("#{db_match[:digest]}")
        }
        resp : NamedTuple("nodeName": String, "ids": Array(String)) = {
          "nodeName": statuses["nodeName"].as_s,
          "ids":      filterd_statuses.map { |s| s.dig("containerID").as_s.gsub("containerd://", "")[0..12] },
        }

        resp
      end.compact.flatten
    end
  end
end
