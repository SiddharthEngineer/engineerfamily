FROM python:3.12-slim

WORKDIR /app

COPY services/app/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY services/app/ ./
COPY templates/ ./templates/

EXPOSE 8000

CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8000", "--workers", "2"]