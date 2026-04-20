FROM node:22-alpine AS vite-builder

WORKDIR /frontend

ARG UMAMI_APP_ID
ENV VITE_UMAMI_APP_ID=${UMAMI_APP_ID}

COPY services/app/vite/package*.json ./
RUN npm ci

COPY services/app/vite/ ./
COPY services/app/portfolios/ ../portfolios/
RUN npm run build

FROM python:3.12-slim

WORKDIR /app

COPY services/app/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY services/app/ ./
COPY --from=vite-builder /frontend/dist ./vite/dist

EXPOSE 8000

CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8000", "--workers", "2"]