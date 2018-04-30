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
--google-tags gitlab \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
gitlab1


gcloud compute firewall-rules create gitlab-access \
--allow tcp:80,tcp:8080,tcp:443 \
--target-tags=gitlab \
--description="Allow gitlab access" \
--direction=INGRESS

export DOCKER_HOST_IP=$(docker-machine ip $DOCKER_MACHINE_NAME)



#https://docs.gitlab.com/runner/install/docker.html
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest


docker exec -it gitlab-runner gitlab-runner register


### monitoring-1 ###

#access to prometheus
gcloud compute firewall-rules create mon-access \
--allow=tcp:9090 \
--description="Allow prometheus access" \
--target-tags=prometheus \
--direction=INGRESS

#create prometheus vm
docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-tags prometheus \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
mon-vm

eval $(docker-machine env mon-vm)

#start prometheus container
docker run --rm -p 9090:9090 -d --name prometheus prom/prometheus


cat <<! > monitoring/prometheus/Dockerfile
FROM prom/prometheus
ADD prometheus.yml /etc/prometheus
!

#build srv images
for _d in ui comment post-py
do
  (
  cd src/$_d && sh docker_build.sh
  )
done

#push them
for _img in post comment ui prometheus
do
  docker push $USER_NAME/$_img
done
