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
- мамонтятская технология разделения доступа к общему ресурсу и его представления, man объемный и понятен только хардкорным юниксоидам
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
