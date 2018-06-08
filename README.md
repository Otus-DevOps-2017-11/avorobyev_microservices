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

docker build -t ${USER_NAME}/prometheus .
```
- Добавляем как еще один сервис в docker compose

```yaml
monitor:
  image: ${USER_NAME}/prometheus
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
  (
  cd src/$_d && sh docker_build.sh
  )
done

docker-compose -f docker-compose.yml up -d #явно указываем конфиг, чтоб не применять override файл
```

- Отправляем образы на docker hub

  ```bash
  for _img in post comment ui prometheus
  do
    docker push $USER_NAME/$_img
  done
  ```

  Результат здесь: https://hub.docker.com/r/alxbird/

# Задание 23

Мониторинг и алармы

## Модель

### prometeus
 предоставляет приложениям сбор данных через библиотеки. Видел для java, ruby, go, python. Данные собираются нескольким способами:

- счетчик
- шкала
- гистограмма
- сумма

Для обработки и визуализаций в api есть богатый набор функций. Например:  

```
histogram_quantile(0.95, sum(rate(ui_request_latency_seconds_bucket[5m])) by (le))
```  
Попробую разобрать.  

- ui_request_latency_seconds_bucket[5m] - vector range, массив значений метрики за последние 5 минут. Скорей двумерный массив, где первое измерение - набор меток, второе - последовательность пар (значение, время)

- rate(...) - скорость изменения во времени значения из второго измерения. На выходе второе измерение схлопывается в одно значение.

- sum(...) by (le) - сумма значений, объединенная по значению метки le ( по идентификатору бакета гистограммы ), то есть суммируем скорость роста времени обработки запросов

- histogram_quantile(0.95, ... ) -  скорость роста времени обработки запроса, которая не будет достигнута в 95% случаев. Тут у меня возникают проблемы осмысления. Что эта характеристика дает? Какова природа и мотивация ее вычисления?

### cadvisor
 собирает данные по контейнерам через интерфейсы хоста, формирует метрики по правилам prometheus. В терминологи prometeus он экспортер.  

### grafana
 сервис визуализации различных даных. В качестве источника может быть prometheus. Раздел представления - дэшборд. На него уже выводятся графические представления данных. Дэшборды можно создавать свои или импортировать готовые из коллекции на сайте.  

### alertmanager
 рассылает нотификации о событиях. События поставляются через http интерфейс. В его конфигурации определяются каналы и способы рассылки. События определяются правилами, подсоединяемыми к конфигурации prometheus. Там же определяется точка доступа к рассыльщику. Далее при срабатывании правила prometheus генерирует описание события и отправляет на рассыльщик.

## Действия

- Разделили конфигурацию на основную и подсистему мониторинга.

- В мониторинг добавили добавили сервисы cadvisor, grafana, alertmanager.

```yaml
#docker/docker-compose-mon.yml
cadvisor:
  image: google/cadvisor:latest
  volumes:
    - /:/rootfs:ro
    - /var/run:/var/run:rw
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
    - /dev/disk/:/dev/disk:ro
  ports:
    - 8080:8080
  networks:
    back_net:

grafana:
  image: grafana/grafana
  volumes:
    - grafana_data:/var/lib/grafana
  environment:
    GF_SECURITY_ADMIN_USER: admin
    GF_SECURITY_ADMIN_PASSWORD: secret
  depends_on:
    - monitor
  ports:
    - 3000:3000
  networks:
    back_net:

alert:
  image: ${USER_NAME}/alertman
  command:
  - '--config.file=/etc/alertmanager/config.yml'
  ports:
  - 9093:9093
  networks:
    back_net:
```

- Для cadvisor определили точку сбора данных в конфиге prometheus.

```yaml
#monitoring/prometheus/prometheus.yml
- job_name: 'cadvisor'
  static_configs:
    - targets:
      - cadvisor:8080
```

- Для grafana определили http сервис prometheus как источник данных. Далее ссылаемся на него при создании графиков в дэшбордах. Создали два дэшборда с визуализацией метрик сервиса UI и бизнес логики.

- В alertmanager определили канал slack

```yaml
#monitoring/alertmanager/config.yml
receivers:
- name: 'slack-notifications'
  slack_configs:
  - channel: '#a-vorobyev'
```

- В prometheus определили правила наступления события и его структуру в файле ```monitoring/prometheus/alerts.yml```. А также задали интерфейс alertmanager как как пункт назначения событий.

```yaml
#monitoring/prometheus/prometheus.yml
rule_files:
  - alerts.yml

alerting:
  alertmanagers:
    - scheme: http
      static_configs:
        - targets:
          - alert:9093
```

Образы: https://hub.docker.com/r/alxbird/


# Задание 25

Логирование. Пожелания:
- хорошо бы иметь логи, приведенные к универсальному виду
- быстрый доступ
- машинная обаботка
- в одном месте

В общем, центализованная система логирования состоит из поставщиков (shippers), индексатора/аггрегатора (indexer), системы хранения (storage), графического интерфейса.

Применяем связку Elastik Stack (ELK), где сборщик логов заменен на fluentd. Так из ELK получается EFK.

### Модель

В контейнере есть драйвер логирования. Он перехватывает стандартные потоки ввода вывода приложения и далее поступает с ними согласно своей реализации. По умолчанию собранные данные пишутся в json файл. Посмотреть ```docker logs <container name|container id>```. Разработчики сервисов должны учитывать эту особенность и не писать логи в места, отличные от STDOUT/STDERR. Или сразу отгружать в сервис логирования.

Для промышленных сценариев драйвер меняется на нужный.

Реализация EFK состоит из:
 - Поставщика логов  ( fluentd драйвер логирования или API логирования приложения, интегрированное с fluend )
 - Сборщика логов. Fluend сервер. Представляет точку сбора логов со всех сервисов системы. Агрегирует, фильтрует и разбирает лог-записи. Отправляет логи в систему хранения.
 - Системы хранения логов. Elastic Search. Хранит данные и индексирует.
 - Графический интерфейс. Kibana. Для выборки и просмотра через web.

Немного про сборщик. Внутри единица логирования представлена объектом - event с атрибутами tag, timestamp, log-record. События поступают чере входной интерфейс - source на выход - output. Таким образом формируется поток - event stream. В поток можно подключать функциональные элементы - фильтры, преобразователи и пр. Они будут применяться в порядке расположения в конфиге.

### Действия

- Добавили описание системы логирования ```docker/docker-compose-log.yml```

- Описали образ и конфигурацию сервера Fluentd ```docker/fluentd/*```

- Добавили несколько фильтров в конфиг Fluentd. Последний по спецзаданию. Копать grok не захотелось, сделал на regex.

```xml
<filter service.ui>
  @type parser
  format /service=(?<service>.*?) \| event=(?<event>.*?) \| path=(?<path>.*?) \| request_id=(?<request_id>.*?) \| remote_addr=(?<remote_addr>[\d.]+?) \| method= (?<method>\w+?) \| response_status=(?<response_status>\d{3})$/
  key_name message
  reserve_data true
</filter>
```
- Посмотрели логи через kibana и трейсы через zipkin.

### Проблемы

- Не собирался образ post. Подсмотрел у коллег.
- Главная страница UI с ошибкой из за неподнятого zipkin. В общем, это даже хорошо, есть на что позырить в kibana )
- Сервисы с драйвером логирования fluentd становятся зависимыми от fluentd сервера.


# Задание 27

Оркестрация. Docker swarm.

### Модель

Множество сервисов, исполняется на множестве узлов. Связь сервиса с узлом задается через конфиг. Узлы здесь - всего лишь ресурсы, которые нужно задействовать для исполнения конфига. Реализует все это специальная сущность - оркестратор. Даже если связи не заданы, оркестратор создает их сам, используя стратегии по умолчанию.

Основные сущности:

- Узлы  
  Разделяются по ролям:

  - Управляющий  
    Принимает команды управления объектами swarm

  - Исполнитель  
    Исполняет директивы управляющего на запуск экземпляров сервиса и отчитывается об их состоянии.

  Только один узел исполняет команды управления. Он выбирается множеством управляющих узлов в процессе кворума.
  Остальные перенаправляют команды на него.

- Сервисы  
  Представляет собой целевую конфигурируемую сущность. Она описывает то, что запускается в swarm, и как сопровождать изменения ее жизненного цикла.

  Публикуемые порты сервиса выносятся в общее множество swarm, и доступны при обращении на любой узел.

- Задачи  
  Экземпляры сервисов. Все они доступны через общую точку доступа, определенную для сервиса. Балансировка в цикле. Реализуется функционалом управляющего узла.

- Стэк  
  Известное множество сервисов.

Сетевые особенности.  

Создается overlay сеть ingress.

### Действия

- подготовка
```bash
function switch_docker_host {
  local in_hostname=$1
  eval $(docker-machine env $in_hostname)
}

export GCP_PROJ=docker-xyz
export USER_NAME=dodocker
export STACK_NAME=DEV
declare -a MACHINES=(master-1 worker-1 worker-2)

#create machines
for _m in ${MACHINES[@]}
do
  docker-machine create --driver google \
     --google-project $GCP_PROJ \
     --google-zone europe-west1-b \
     --google-machine-type g1-small \
     --google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
     $_m
done
```

- создать swarm
```bash
#создать manager
switch_docker_host  master-1
docker swarm init

#добавить workers
switch_docker_host  worker-1
docker swarm join --token xxxxxxxxxxxxxx 10.132.0.2:2377
```

- создать stack
```bash
docker stack deploy --compose-file=<(docker-compose -f docker-compose-stack.yml config 2>/dev/null) DEV
```

- посмотреть детали (на управляющем узле)
```bash
#какие узлы
docker node ls

#детали узла
docker node inspect <node_name|self>

#какие сервисы
docker stack services DEV

#какие задачи
docker stack ps DEV

#задачи сервиса
docker service ps <service_name>

#детали сервиса
docker service inspect <service_name> --pretty
```

- изменить объекты
```bash
#добавить метаданные к узлу
docker node update --label-add reliability=high master-1

#изменить количество экземпляров сервиса
docker service update --replicas 0 DEV_ui
```

### Ответы на вопросы

- При добавлении узла на нем запустились задачи сервисов, с режимом развертывания global. Таким оказался сервис node-exporter.

  Далее, увеличив количество реплик остальных сервисов, можно наблюдать, как они занимают новое пространство в лице добавленного узла.    Уже существующие реплики не переместились. Похоже, наблюдаются результаты использования планировщиком стратегии spread.


# Задание 28

Системы управления контейнеризированными приложениями. Kubernetes.

### Модель

Есть кластер. В нем узлы. Узлы классифицируются на управляющие и просто узлы. На управляющих узлах исполняются процессы поддержки целостности кластера и поддержки сервисов в требуемом состоянии, а также  хранится состояние самого кластера. На остальных работают сервисы, несущие бизнес ценности.

Компоненты управляющего узла  

- api-server  
  Предоставляет API. Принимает и обрабатывает запросы.

- kube-controller-manager  
  Менеджер контроллеров. Каждый контроллер отвечает за состояние объектов в своем скоупе.

- kube-scheduler  
  Управляет размещещением подов с приложениями на основании инфы о доступных ресурсах в кластере.

Компоненты просто узла.

- kubelet  
 Кубеленок )  piglet ведь поросенок ))  Если серьезно, интерфейс для управления узлом. Сюда стучатся компоненты с управяющей ноды. Kubelet также может что то запрашивать.

- kube-proxy  
 Управляет сетевым трафиком. Активируется при запуске какого либо сервиса в кластере.

- container runtime  
 Контейнерное ПО, в котором будет работать приложение. Docker или rkt.

- pods.
 Абстракция от container runtime. Представление приложения в домене kubernetes. Наименьшая управляемая единица в кластере.

Управляется все это через cli фронтенд  - kubectl. Он запрашивает api-server. Типичные примеры использования:

```bash
kubectl get pods
kubectl get services
kubectl get nodes
```

Дальше ничего не помню. Отшибло после прохождения тяжелого пути )

### Действия

После тяжелых было грустно, но я собрался и сделал задание так:

```bash
function make_manifest {
  local in_app_name=$1
  local in_image_name=$2
  echo -n "\
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: ${in_app_name}-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${in_app_name}
  template:
    metadata:
      name: ${in_app_name}
      labels:
        app: ${in_app_name}
    spec:
      containers:
      - image: ${in_image_name}
        name: ${in_app_name}
"
}

declare -a APPS=(post ui mongo comment)
USER_NAME=alxbird
declare -A APP_IMAGE=(
  [post]=$USER_NAME/post
  [ui]=$USER_NAME/ui
  [comment]=$USER_NAME/comment
  [mongo]=mongo:3.2
)

for _app in ${APPS[@]}
do
  _manifest=$(make_manifest $_app ${APP_IMAGE[$_app]})
  echo "$_manifest" > ${_app}_deployment.yml
  echo "$_manifest" | kubectl apply -f -
done
```

в результате

```bash
admine@ubun-vm:~/MyBox/Projects/Otus/avorobyev_microservices/kubernetes$ kubectl get pods
NAME                                  READY     STATUS    RESTARTS   AGE
busybox-68654f944b-6fnmb              1/1       Running   1          1h
comment-deployment-7784766558-dwg52   1/1       Running   0          1m
mongo-deployment-778dcd865b-29vhn     1/1       Running   0          1m
nginx-65899c769f-qf86h                1/1       Running   0          1h
post-deployment-c9697fc94-hs7kf       1/1       Running   0          1m
ui-deployment-78fb684db-sktc7         1/1       Running   0          1m
untrusted                             1/1       Running   0          1h
admine@ubun-vm:~/MyBox/Projects/Otus/avorobyev_microservices/kubernetes$
```

Потом кластер был загашен инструкциями с последней страницы тяжеляка. Аминь.


# Задание 29

Kubernetes. Установка reddit в локальном кластере и в GKE.


### Модель

Каждому объекту можно привязать произвольный набор свойств, где каждое есть пара ключ - значение. Размещаются они в разделе метаданных в подразелах labels и annotations. Первый предназначен для неуникальной идентификации и используется для выборок. Второй для передачи дополнительной семантики для стороннего использования. В конфигурационных файлах объекты связываются друг с другом с помощью labels.

Внутри кластера могут быть заданы namespace'ы. Для упорядочивания объектов внутри кластера. Воспринимается как подкластер.

Работа с kubernetes всегда выполняется в каком то контексте. Контекст - это сочетание кластера, пользователя и пространства имен (не обязательно).

Группу подов обычно заводят через Deployment. В его конфиге определяется логическое выражение. Deployment подтащит поды, для меток которых выражение возвратит true.

Для доступа к подам(приложениям) извне запускаем объект Service. Оно ассоциируется с подами так же, как и Deployment. После запуска имя сервиса разрешается через DNS на всех подах (в одном namespace).

Kubernetes AA. Страшный черный ящик. Ничего не понял, кроме того что все и вся должно проходить AA (service -> service, user -> service). Четкого разбора сценариев нигде не видел. В hardway заводили сертификаты, но попытка осознать механику закончилась выносом мозга. Возможно, стоит смотреть сюда https://kubernetes.io/docs/admin/authentication. Хотя, если из коробки все работает, то может ну его на ... )

### Действия

- Запустил локальный кластер через minikube.

- Создал yml конфиги для развертывания компонентов reddit. Разместил в ```kubernetes\reddit-app```.  

  Предполагаю, что создание дополнительной ассоцииации поды <- сервис для имитации сетевого алиаса приведено в ДЗ просто для ознакомления.  Суть понял, но делать так не стал, оставив сервис mongo и передав его имя через окружения контейнеров post и comment.

  ```yaml
  #kubernetes\reddit-app\post_deployment.yml
  env:
    - name: POST_DATABASE_HOST
      value: mongodb

  #kubernetes\reddit-app\comment_deployment.yml
  env:
    - name: COMMENT_DATABASE_HOST
      value: mongodb
  ```

- Запустил reddit в кластере в пространствах имен default и dev.

- Завел кластер в GKE. Посмотрел на смену контекста после соединения.

- Запустил reddit в кластере GKE в пространстве dev.

### Проблемы

- minikube под windows - это страх и ненависть. Начиная от невозможности работы через прокси, до спонтанных вылетов типа:

```
λ kubectl.exe apply -f comment_deployment.yml
Error from server (Timeout): error when retrieving current configuration of:
&{0xc04397ccc0 0xc043ef8a80 default comment-deployment comment_deployment.yml 0xc043d96658 0xc043d96658  false}
from server for: "comment_deployment.yml": the server was unable to return a response in the time allotted, but may still be processing the request (get deployments.apps comment-deployment)
```

- дэшборд в созданном сегодня кластере не запустился. Причем ни одна из ошибок не относилась к RBAC. Потом обратил внимание на пояснение в вэбе (... Note: Dashboard UI is deprecated. You can find the updated graphical user interface for Kubernetes Engine in the Google Cloud Platform Console Learn more) Возможно, проблема в этом.

# Задание 30

Kubernetes. Сетевой доступ к сервисам и хранение данных.

### Модель

Сетевой доступ к сервису может быть организован несколькими способами. Способ указывается через атрибут type описания сервиса. Возможные значения:  

- ClusterIp
  Сервису выделяется отдельный ip внутри кластера, обращения на него транслируются на поды сервиса грязными трюками с iptables. Манипулирует iptables kube-proxy.
- NodePort  
  На каждой ноде кластера запускается порт из специального диапазона. Обращаясь на этот порт, попадаем на какой то под сервиса.
- LoadBalancer  
  Внешний балансировщик. Запускается провайдер-специфичным способом.

Альтернативный LB способ - задать объект Ingress. Он будет предоставлять единую точку доступа к сервисам с обеспечением балансировки и маршрутизацией трафика по данным из PDU L7 (HTTP). В описании ссылается на сервис, работающий в режиме NodePort. Требует наличия ingress-controller в окружении kubernetes.

Разрешение имен реализуется через переменные окружения, или запускается сервис dns (в отдельном поде).

Для ограничения трафика между подами существуют объекты Network Policies. В них определяем множество подов, направление трафика и white lists для направлений. Пустое множество означает все поды. Пустой white list означает запрещено для всех.

Разделы хранения данных - volumes, описываемые в шаблонах подов, привязаны к жизненному циклу подов. Они не подходят для задач, где требуется постоянно хранить данные. Для этого в кластере создаются специальные разделы - persistent volumes (pv). Увидел три способа работы с такими разделами:

- В шаблоне пода напрямую сослаться на хранилище, используя специфичные для провайдера атрибуты.
- Создать pv. Создать persistent volume claim (pvc) - запрос на ресурс хранилища. В шаблоне пода сослаться на pvc.  При запуске пода pvс подтянет подходящий pv.
- Создать storageClass - фабрику pv. Создать pvc со ссылкой на фабрику. В шаблоне пода сослаться на pvc. При старте пода, если не будет свободного подходящего для pvc раздела, фабрика создаст нужный динамически.

### Действия

- Попробовал разные типы сервисов.

- Загасил поды c DNS, убедился в их полезности ) Вернул обратно.

- Создал ingress с поддержкой TLS.

- Ограничил доступ к базе данных только для сервисов post и comment c помощью NetworkPolicy.

- Организовал сохранность данных mongo несколькими способами:
    - прямой ссылкой на диск в GCE
    - комбинацией Deployment -> PVC -> PV
    - комбинацией Deployment -> PVC -> StorageClass

### Дополнительное задание

Мой рецепт пересоздания секрета для ленивых. За инфу о пересоздании ингресса спасибо коллегам.
```bash
kubectl get secret ui-ingress -o=yaml -n dev | grep -v "creationTimestamp|uid|resourceVersion" > reddit-app\ui-ingress-secret.yml
kubectl delete -f reddit-app\ui-ingress.yml -f reddit-app\ui-ingress-secret.yml -n dev
kubectl apply -f reddit-app\ui-ingress-secret.yml -f reddit-app\ui-ingress.yml -n dev
```
