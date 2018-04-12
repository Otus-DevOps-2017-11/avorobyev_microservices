# Задание 14

Установка на win8 не прокатила, нужна win10 pro. Поставил на linux vm.  

Базовые команды:
```bash
docker run <image> <cmd> #создать контейнер из указанного образа, запустить в нем процесс cmd, -d - демон?
docker images #посмотреть имеющиеся образы
docker image ls #то же самое
docker ps #посмотреть работающие контейнеры, с флагом -a выводит и не работающие
docker container ls --all #то же самое
docker start <container id> #запустить контейнер
docker kill <container id> #остановить по SIGKILL
docker stop <container id> #остановить по SIGTERM
docker attach <container id> #присоединится к IO потокам контейнера
docker exec <container id> <cmd> #выполнить команду в контейнере
docker rm <container ids> #удалить контейнеры
docker rmi <image ids> #удалить образы
```

# Задание 15

namespace
- технология разделения доступа к общему ресурсу и его представления, man понятен только хардкорным юниксоидам
- --network=host - понял как указание использовать в контейнере сетевой стек хоста
- --pid host - в контейнере видятся все процессы с docker host, процесс контейнера где то среди них

docker-machine
- создает docker host где-либо с помощью драйвера: gcp, aws, virtualbox (локально на win и mac), ...
- соединяет машину админа с docker host'ом; и через своего клиента админ управляет удаленным docker'ом: образами и контейнерами.

```bash
docker-machine create --driver <driver name> <driver params> <docker host name> #создать docker host
docker machine ls #посмотреть, какие есть
eval $(docker machine env <docker host name>) #ассоциироваться с указанным docker host
#TODO: как диссоциироваться?
docker build -t <image_name:image_tag> . #собрать образ, используя описание и файлы в текущем каталоге
docker tag <dh_user/dh_repository:dh_tag> <image_name:image_tag> . #пометить образ по правилам docker hub
docker login #зайти на docker hub
docker push <dh_user/dh_repository:dh_tag> #отправить образ в репозиторий
```

# Задание 16

Образы состоят из слоев. Слои создаются комадами из Dockerfile (ADD COPY RUN). Число слоев желательно уменьшать, объединяя команды в последовательности. Также нужно следить, чтоб в образ не попали лишние файлы из контекста сборки. Еще по возможности следует уменьшать объем записи в модифицируемый слой контейнера. Ценные данные выносятся из контейнера с помощью volume, bind mounts. Есть еще tmpfs, это вроде как для хранения временных данных в памяти, не затрагивая модифицируемый слой.

Слайд с модификацией Dockerfile для ui - дезинформация. У меня образ распух на несколько десятков мегабайт. Это видно по размеру слоя, добавляемому разными версиями RUN (docker image history <image>):

старая версия ( ui/Dockerfile.zero):
aa244c9d7133        2 hours ago         /bin/sh -c apt-get update -qq && apt-get ins…   15.6MB

новая версия (ui/Dockerfile):
1b5a788ee9cc        2 hours ago         /bin/sh -c mkdir $APP_HOME &&   apt-get upda…   65.2MB

## Дополнительное задание 1

Поменять сетевые алиасы. Поробовал через файл с переменными окружения:

```bash
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
```

## Дополнительное задание 2

- Собрать на alpine.
Нужно знать, как поставить окружение ruby на голый образ alpine. Затратно. Нужно изучать пакетный менеджер alpine и быть ruby прогером, а это не входит в мои планы ;)

- Изыскать способ уменьшить образ.
Начитавшись док, решил попробовать multistage build. Но тут снова встают рубишные грабли, потому что я понятия не имею какие артефакты на выходе сборщика. Экспериментальный файл: ui/Dockerfile.trashy. Объем меньше, чем у изначального образа, но контейнер не рабочий. Облом (
