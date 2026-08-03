{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/ex-broadcaster-user-data.log",
            "log_group_name": "${system_log_group}",
            "log_stream_name": "{instance_id}/user-data"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${system_log_group}",
            "log_stream_name": "{instance_id}/syslog"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "ExBroadcaster",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}",
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
      %{ if gpu_enabled ~}
      ,
      "nvidia_gpu": {
        "measurement": [
          "utilization_gpu",
          "utilization_memory",
          "memory_used",
          "memory_total",
          "temperature_gpu",
          "power_draw",
          "encoder_stats_session_count",
          "encoder_stats_average_fps",
          "encoder_stats_average_latency"
        ]
      }
      %{ endif ~}
    }
  }
}
