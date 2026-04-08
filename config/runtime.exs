import Config

config :ex_broadcaster,
  storage: if(System.get_env("S3_BUCKET"), do: :s3, else: :file),
  s3_bucket: System.get_env("S3_BUCKET", ""),
  s3_prefix: System.get_env("S3_PREFIX", "hls")
