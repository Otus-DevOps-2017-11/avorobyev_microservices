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

docker pull mongo:latest
docker build -t alxbird/post:1.0 ./post-py
docker build -t alxbird/comment:1.0 ./comment
docker build -t alxbird/ui:1.0 ./ui

docker network create reddit

docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:latest
docker run -d --network=reddit --network-alias=comment alxbird/comment:1.0
docker run -d --network=reddit --network-alias=post alxbird/post:1.0
docker run -d --network=reddit -p 9292:9292 alxbird/ui:1.0

cat > envfile <<-!
COMMENT_SERVICE_HOST=commenter
POST_SERVICE_HOST=poster
COMMENT_DATABASE_HOST=commenter_db
POST_DATABASE_HOST=poster_db
!

docker run -d --network=reddit --network-alias=poster_db --network-alias=commenter_db mongo:latest
docker run -d --network=reddit --network-alias=commenter --env-file=./envfile alxbird/comment:1.0
docker run -d --network=reddit --network-alias=poster --env-file=./envfile alxbird/post:1.0
docker run -d --network=reddit -p 9292:9292 --env-file=./envfile alxbird/ui:1.0
