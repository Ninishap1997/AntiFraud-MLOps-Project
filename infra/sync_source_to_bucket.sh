export BUCKET_NAME="$(terraform output -raw bucket_name)"
export AWS_ACCESS_KEY_ID="$(terraform output -raw s3_access_key_id)"
export AWS_SECRET_ACCESS_KEY="$(terraform output -raw s3_secret_access_key)"
export AWS_DEFAULT_REGION="ru-central1"

aws --endpoint-url https://storage.yandexcloud.net \
  s3 sync s3://otus-mlops-source-data/ "s3://${BUCKET_NAME}/source-data/" \
  --copy-props none