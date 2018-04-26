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

# Задание 17

## Сети

Они здесь такие:

- none  
  в контейнере доступен только loopback интерфейс.
- bridge  
  сеть контейнеров отделяется от сети хоста программным маршрутизатором
- host  
  контейнеры разделяют сетевой стек хоста
- overlay  
  объединение bridge networks нескольких хостов
- macvlan  
  контейнер получает доступ к физическому интерфейсу. Не помню деталей, но вроде как интерфейс контейнера является подинтерфейсом физического nic. Почему vlan - L2 трафик метится согласно разделению по сетям.

Как правило работают с bridge сетями. Причем, они делятся на default и определяемую пользователем. Отличие последней в следующем:  

- автоматически открываются порты сервисов всем узлам сети.
- DNS. В сети по умолчанию контейнеры могут обращаться друг к другу только по адресам.
- возможность управления составом сети On the fly
- конфигурируемый мост

В пользовательской bridge сети контейнеры доступны по имени. Также можно назначать сетевые алиасы как дополнительные параметры для docker run. Алиас здесь можно рассматривать как свойство ассоциации сеть - контейнер.  

Для сети создается устройство с префиксом br. Сетевые интерфейсы контейнеров можно видеть на хосте как устройства veth* в выводе ifconfig. Если поставить специальные утилиты, с их помощью можно увидеть группировку этих устройств по мостам. Публикация портов сервисов реализована манипуляцией iptables хоста и запуском проксирующего приложения - docker-proxy.   

### Ответы на вопросы

- слайд 11. Из всех контейнеров запустится только один. Так как все они используют общий сетевой стек, им доступно одно множество портов. Первый контейнер займет порт, остальные не смогут и остановятся с ошибкой.

- слайд 12. Комады просто прелесть. Настоящая магия ))) Хорошо, включаем monkey see monkey do, и в случае с ```--network=none``` в списке обнаруживается еще одна запись.


## Docker compose

Утилита - надстройка, позволяющая описывать сервисы в виде yaml и управлять ими как единым целым. Ставится как python модуль.

В целом, все понятно. Но, по ходу выполнения упражнений в голове произошел коллапс в классификации переменных. Решил упорядочить их здесь для лучшего запоминания:  

- Переменные сборки образа. Директива ARG в Dockerfile. Передаются как параметры командной строки в ```docker build```. В compose - как список service_name.build.args.

- Переменные окружения в контейнере. Директива ENV в Dockerfile. В compose - как список service_name.environment.

- Переменные в compose файле. Берутся значения одноименных переменных окружения. Значения по умолчанию могут передаваться через файл ```.env``` в директории рядом с compose файлом. Окружение имеет приоритет.

### Дополнительное задание

- Префикс compose проекта по умолчанию берется как имя директории. Также можно передавать как параметр командной строки ```-p``` или переменную окружения ```COMPOSE_PROJECT_NAME```. Передаю через .env файл.

- Overide файл. Используются свойства переопределения некоторых директив Dockerfile. Предполагаю, это реализуется через соответствующие опции ```docker run```.  
Для реализации доступа к исходникам из контейнера используются bind mounts. Загвоздка в том, что эти файлы должны находится на docker-host. И их нужно переносить туда самостоятельно:

```bash
docker-machine ssh docker-host mkdir src
for _dir in comment post-py ui
do
  docker-machine scp -r $_dir docker-host:src
done
```

далее в определении bind mount использовать путь:

```yaml
volumes:
  - /home/docker-user/src/comment:/app
```

Есть сомнения в полезности такого доступа, - ну помеяем исходники, а кто собирать будет? ... и перезапускать приложение с новыми бинарями?

# Задание 19

Gitlab. Это инструменты, разные, с единой точкой доступа и интерфейсом.

## Установка

 Ставим omnibus из docker образа. Для того, чтоб удовлетворить требованиям, создаем отдельную ВМ с 4ГБ памяти и 50ГБ диском:

```bash
#create vm
docker-machine create --driver google \
--google-project docker-xxx \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-disk-size 50 \
--google-tags gitlab
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
docker-gitlab

#give access to gitlab services
gcloud compute firewall-rules create gitlab-http \
--allow tcp:80,tcp:8080,tcp:443 \
--target-tags=gitlab \
--description="Allow http for gitlab" \
--direction=INGRESS

#select machine
eval $(docker-machine env docker-gitlab)
```

Далее, с помощью docker-compose запускаем контейнер из образа gitlab/gitlab-ce:latest. Внешний адрес передаем через переменную DOCKER_HOST_IP:

```bash
export DOCKER_HOST_IP=$(docker-machine ip docker-gitlab)
docker-compose up -d
```

Как выяснилось, предварительно не нужно создавать никаких каталогов для bind mounts, они создаются сами.

## Использование

### Модель
Есть проекты в группах проектов. Проект хранит исходный код и доступен как удаленный git репозиторий. К проекту привязан процесс CI/CD - pipeline, описание которого в файле .gitlab-ci.yml в корневой папке проекта.

Pipeline запускается по событию изменения проекта (git commit). Он в свою очередь требует среды исполнения, именуемую здесь Runner.

### Действия
В общем, через вэб создаем, группу, добавляем туда проект. Проект подключаем как удаленный репозиторий локального проекта microservices. Подкладываем заготовку с описанием pipeline.  

Внимание, магия, добавляем runner )))

```bash
#стартуем непонятный контейнер, кажись, просто набор инструментов для управления раннерами
docker run -d --name gitlab-runner --restart always \
-v /srv/gitlab-runner/config:/etc/gitlab-runner \
-v /var/run/docker.sock:/var/run/docker.sock \
gitlab/gitlab-runner:latest

#ассоциируем его с сервером Gitlab
docker exec -it gitlab-runner gitlab-runner register
#...отвечаем на вопросы по подсказке из слайда, самые главные, - какие url сервера и токен
```

Далее тривиально, - добавляем приложение, тест для него и зависимость для теста. Дописываем pipeline так, чтоб в нем могли запускаться rubi приложения и добавляем вызов теста на стадии тестирования. Коммитим, наслаждаемся )


### Проблемы

- после перезапуска docker хоста меняется внешний адрес, старый остается в настройках проекта.

## Дополнительное Задание

Декомпозировать можно таким образом  
- вытащить токен из инстанса гитлаба
- в цикле регистрировать раннеры, на каждой итерации пользуясь многочисленными параметрами ```gitlab-runner register -h```


# Задание 20

Есть возможность управлять способом запуска задач через атрибут when. Например, установив его в manual, соответствующая задача  не будет запускаться автоматически. Также можно определять условия запуска через комбинацию атрибутов only/except.  

Осталось загадкой, почему регулярное выражение в only применяется только к тэгу, ведь явно на это ничего не указывает. Не могу назвать прозрачной эту логику.  

Задачи pipeline могут содержать указание на окружение. Под окружением понимаю некую инфраструктуру, куда устанавливаются результаты работы сборщика.  

Но, как связать инфраструктуру с окружением в гитлаб? Предполагая под ней набор контейнеров, как установить на них ПО, зная, что задача деплоя выполняется тоже в контейнере. То есть нужно разобраться как работать с контейнерами из контейнера.  Перспективы сего мутны и энтузиазма не вызывают.

### Проблемы

Столкнулся с невозможность зарегистрировать существующий docker host на другой рабочей машине. Пришлось сносить и создавать новый. В интернете простых решений не нашел.


# Задание 21

Изучаем сервис мониторинга Prometheus.

## Модель

Объекты мониторинга - jobs (сервисы). С каждым из них ассоциирован список экземпляров сервиса. Экземпляр предоставляет http точку доступа, по пути /metrics которой предоставляется набор данных специального формата.  

```
<metric name>{<label name=label value>... } <metric value>
```  

При сборе каждому элементу данных присваивается метка времени.  

Наблюдаемый сервис может иметь собственную реализацию интерфейса мониторинга. Также возможна установка специального модуля - экспортера, извлекающего данные из сервиса и преобразующего их в формат сервера мониторинга.

## Действия.

### Установка.

- Собираем кастомный образ с файлом конфигурации

```bash
cat <<! > Dockerfile
FROM prom/prometheus
ADD prometheus.yml /etc/prometheus
!

docker build -t prometheus-custom .
```
- Добавляем как еще один сервис в docker compose

```yaml
monitor:
  image: prometheus-custom
  ports:
    - 9090:9090
  volumes:
    - prometheus_data:/prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--storage.tsdb.retention=1d'
  networks:
    front_net:
    back_net:
```

- Добавляем экспортер для докер хоста как еще один сервис в docker compose

```yaml
node-exporter:
  image: prom/node-exporter:v0.15.2
  user: root
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /:/rootfs:ro
  command:
    - '--path.procfs=/host/proc'
    - '--path.sysfs=/host/sys'
    - '--collector.filesystem.ignored-mount-points="^/(sys|proc|dev|host|etc)($$|/)"'
  networks:
    back_net:
```

- Собираем образы приложений, стартуем, изучаем вэб интерфейс

```bash
for _d in ui comment post
do
  ( export USER_NAME=me
  cd src/$_d && sh docker_build.sh
  )
done

docker-compose -f docker-compose.yml up -d #явно указываем конфиг, чтоб не применять override файл
```
