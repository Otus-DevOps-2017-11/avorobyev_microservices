docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type g1-small \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
docker-host


gcloud compute firewall-rules create reddit-app \
--allow tcp:9292 --priority=65534 \
--target-tags=docker-machine \
--description="Allow TCP connections" \
--direction=INGRESS


docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:latest
docker run -d --network=reddit --network-alias=comment alxbird/comment:1.0
docker run -d --network=reddit --network-alias=post alxbird/post:1.0
docker run -d --network=reddit -p 9292:9292 alxbird/ui:1.0

COMMENT_SERVICE_HOST
POST_SERVICE_HOST
COMMENT_DATABASE_HOST
POST_DATABASE_HOST
