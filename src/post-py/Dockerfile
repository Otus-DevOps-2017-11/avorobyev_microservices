FROM python:3.6.4-alpine
#RUN pip install flask pymongo
WORKDIR /app
ADD . /app
RUN apk update && apk add build-base #stolen in honest way
RUN pip install -r /app/requirements.txt
ENV POST_DATABASE_HOST post_db
ENV POST_DATABASE posts
CMD ["python3", "post_app.py"]
