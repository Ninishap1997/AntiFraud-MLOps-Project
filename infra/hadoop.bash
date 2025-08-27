ssh -i ~/.ssh/id_rsa ubuntu@62.84.116.111

hdfs dfs -mkdir -p /data/otus/source-data
hadoop distcp s3a://${BUCKET_NAME}/source-data/ hdfs:///data/otus/source-data/
hdfs dfs -ls -R /data/otus/source-data | head -n 50