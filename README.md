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

Сравнить вывод. В первом случае процессы в контейнере, во втором на хосте. Предположу, что в последнем случае отображаются процессы вне неймспейса контейнера на моей тачке. 
