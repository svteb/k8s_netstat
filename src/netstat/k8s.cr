require "../"

module Netstat
	module K8s
		def self.get_mariadb_pod_container_statues
			pods = self.get_mariadb_pods_by_digest

			db_pod_ips = self.get_pods_ips(pods)

			Log.info { "DB Pods: #{db_pods_ips}" }
			
			pod_statuses = self.get_pods_statuses(pods)

			self.get_pods_container_statuses(pod_statuses)
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
			   "nodeName" => i.dig("spec", "nodeName")
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
			  filterd_statuses = statuses["statuses"].as_a.select{ |x|
				x.dig("ready").as_bool &&
				x && x.dig("imageID").as_s.includes?("#{db_match[:digest]}")
			  }
			  resp : NamedTuple("nodeName": String, "ids" : Array(String)) = 
			  {
				"nodeName": statuses["nodeName"].as_s, 
			   "ids": filterd_statuses.map{ |s| s.dig("containerID").as_s.gsub("containerd://", "")[0..12]}
			  }
		
			  resp
			end.compact.flatten
		end
	end
end