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
docker build -t post:1.0 ./post-py
docker build -t comment:1.0 ./comment
docker build -t ui:1.0 ./ui

docker network create reddit

#docker run -d --network reddit --network-alias post_db --network-alias comment_db mongo:latest
docker run -d --network reddit --network-alias post_db --network-alias comment_db  --mount src=reddit_db,target=/data/db mongo:latest
docker run -d --network reddit --network-alias comment comment:1.0
docker run -d --network reddit --network-alias post post:1.0
docker run -d --network reddit -p 9292:9292 ui:1.0

cat > envfile <<-!
COMMENT_SERVICE_HOST=commenter
POST_SERVICE_HOST=poster
COMMENT_DATABASE_HOST=commenter_db
POST_DATABASE_HOST=poster_db
!

docker run -d --network reddit --network-alias poster_db --network-alias commenter_db mongo:latest
docker run -d --network reddit --network-alias commenter --env-file ./envfile comment:1.0
docker run -d --network reddit --network-alias poster --env-file ./envfile post:1.0
docker run -d --network reddit -p 9292:9292 --env-file ./envfile ui:1.0


docker-machine mount docker-host:src .
fuse: mountpoint is not empty
fuse: if you are sure this is safe, use the 'nonempty' mount option
exit status 1

docker-machine ssh docker-host mkdir src
for _dir in comment post-py ui
do
  docker-machine scp -r $_dir docker-host:src
done


#create machine for gitlab
docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-disk-size 50 \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
docker-gitlab


gcloud compute firewall-rules create gitlab-http \
--allow tcp:80,tcp:8080,tcp:443 \
--target-tags=docker-gitlab \
--description="Allow http for gitlab" \
--direction=INGRESS


#bind mounts created with root permissions
ls -la /srv/gitlab/
total 20
drwxr-xr-x  5 root root 4096 Apr 17 17:04 .
drwxr-xr-x  3 root root 4096 Apr 17 17:04 ..
drwxrwxr-x  3 root root 4096 Apr 17 17:04 config
drwxr-xr-x 10 root root 4096 Apr 17 17:04 data
drwxr-xr-x  8  998 root 4096 Apr 17 17:04 logs
